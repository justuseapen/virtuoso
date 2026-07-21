defmodule Virtuoso.Budget do
  @moduledoc """
  Cluster-global token budget — an Ensemble safety property, not a Fabric
  afterthought.

  Anthropic's limits are per-API-key, so the budget is one named process (in
  Phase 3 a fabric-supervised, failover-capable singleton) holding:

    * **per-conversation daily caps** — bound the blast radius of a single runaway
      conversation,
    * a **global daily cap** — bound total spend across all conversations, and
    * a **kill switch** — an operator stop that refuses everything immediately.

  Caps are genuinely *daily*: counters reset when the day (from `day_fun`,
  default `Date.utc_today/0`) rolls over, so a cap self-heals at the day boundary
  rather than becoming a permanent ceiling.

  Every LLM call passes `check/2` first; on refusal the framework short-circuits
  to a defined fallback response (`refusal_message/0`) instead of spending. The
  N-members-×-judge-×-checker cost multiplier is structural, so this gate exists
  from Phase 1.

  `with_budget/3` is the intended call site: it gates, runs the LLM call only if
  permitted, records actual usage from the result, and returns the fallback tuple
  when over budget — so callers can't forget to record spend.
  """

  use GenServer

  alias Virtuoso.Conversation.Supervisor, as: ConversationSupervisor
  alias Virtuoso.Fabric

  @refusal_message "I've reached my usage limit for now. Please try again later."

  @type name :: atom() | pid()
  @type check_result :: :ok | {:error, :budget_exceeded | :killed}

  defstruct per_conversation_daily: :infinity,
            global_daily: :infinity,
            kill_switch: false,
            per_conversation: %{},
            global: 0,
            day: nil,
            day_fun: &Date.utc_today/0

  # --- public API -----------------------------------------------------------

  @doc """
  The server name the default API targets.

  Single-node (fabric disabled): the local name `Virtuoso.Budget`. Fabric
  enabled: a via tuple through the fabric's registry, so there is **one** budget
  cluster-wide (Anthropic limits are per-API-key) and every node's calls resolve
  to it wherever it lives. On failover the singleton restarts on a survivor with
  fresh counters — the caps are protective ceilings, not billing records, so a
  reset on node loss is the accepted trade.
  """
  @spec name() :: name()
  def name do
    if Fabric.enabled?() do
      Fabric.via(ConversationSupervisor.registry(), __MODULE__)
    else
      __MODULE__
    end
  end

  @doc """
  Start a budget process.

  Options: `:name` (atom or via tuple), `:per_conversation_daily`,
  `:global_daily` (token counts or `:infinity`), `:kill_switch` (boolean).
  """
  def start_link(opts) do
    server = Keyword.get(opts, :name, __MODULE__)

    case GenServer.start_link(__MODULE__, opts, name: server) do
      {:ok, pid} ->
        {:ok, pid}

      # Fabric mode: every node races to start the singleton at boot; the losers
      # map to :ignore so their supervisors drop the child quietly (the same
      # pattern conversations use for netsplit-heal restarts).
      {:error, {:already_started, _pid}} ->
        :ignore
    end
  end

  @doc false
  # Derive the child-spec id from :name so multiple budgets (e.g. per-test, or a
  # future per-tenant budget) can run under one supervisor without id collision.
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc "The response used when a call is refused for budget reasons."
  @spec refusal_message() :: String.t()
  def refusal_message, do: @refusal_message

  @doc """
  Ask whether `conversation_id` may spend right now.

  `:ok` to proceed, `{:error, :killed}` if the kill switch is engaged, or
  `{:error, :budget_exceeded}` if either the per-conversation or global daily
  cap is already reached.
  """
  @spec check(name(), String.t()) :: check_result()
  def check(server \\ name(), conversation_id) do
    GenServer.call(server, {:check, conversation_id})
  end

  @doc """
  Record `tokens` spent by `conversation_id` against both caps.

  A cast: the caller never used the `:ok`, and recording synchronously put two
  round-trips on every LLM call's hot path (review finding 006, partial). Reads
  (`spent/2`, `check/2`) from the same caller still observe the write — casts
  and calls from one process are delivered in order.
  """
  @spec record(name(), String.t(), non_neg_integer()) :: :ok
  def record(server \\ name(), conversation_id, tokens) do
    GenServer.cast(server, {:record, conversation_id, tokens})
  end

  @doc "Engage or release the global kill switch."
  @spec kill_switch(name(), boolean()) :: :ok
  def kill_switch(server \\ name(), engaged?) do
    GenServer.call(server, {:kill_switch, engaged?})
  end

  @doc "Tokens spent by a conversation today."
  @spec spent(name(), String.t()) :: non_neg_integer()
  def spent(server \\ name(), conversation_id) do
    GenServer.call(server, {:spent, conversation_id})
  end

  @doc "Total tokens spent across all conversations today."
  @spec global_spent(name()) :: non_neg_integer()
  def global_spent(server \\ name()) do
    GenServer.call(server, :global_spent)
  end

  @doc """
  Gate an LLM call: check the budget, run `fun` only if permitted, record the
  usage from its `{:ok, %{usage: ...}}` result, and return that result.

  When over budget or killed, `fun` is **not** run; returns
  `{:error, reason, refusal_message()}` so the caller emits the fallback.
  """
  @spec with_budget(name(), String.t(), (-> {:ok, map()} | {:error, term()})) ::
          {:ok, map()} | {:error, term()} | {:error, atom(), String.t()}
  def with_budget(server \\ name(), conversation_id, fun) do
    case check(server, conversation_id) do
      :ok ->
        result = fun.()
        record(server, conversation_id, usage_tokens(result))
        result

      {:error, reason} ->
        {:error, reason, @refusal_message}
    end
  end

  # --- server ---------------------------------------------------------------

  @impl true
  def init(opts) do
    day_fun = Keyword.get(opts, :day_fun, &Date.utc_today/0)

    state = %__MODULE__{
      per_conversation_daily: Keyword.get(opts, :per_conversation_daily, :infinity),
      global_daily: Keyword.get(opts, :global_daily, :infinity),
      kill_switch: Keyword.get(opts, :kill_switch, false),
      day_fun: day_fun,
      day: day_fun.()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:check, _conversation_id}, _from, %{kill_switch: true} = state) do
    {:reply, {:error, :killed}, state}
  end

  def handle_call({:check, conversation_id}, _from, state) do
    state = roll_day(state)
    conv_spent = Map.get(state.per_conversation, conversation_id, 0)

    cond do
      over?(conv_spent, state.per_conversation_daily) ->
        {:reply, {:error, :budget_exceeded}, state}

      over?(state.global, state.global_daily) ->
        {:reply, {:error, :budget_exceeded}, state}

      true ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:kill_switch, engaged?}, _from, state) do
    {:reply, :ok, %{state | kill_switch: engaged?}}
  end

  def handle_call({:spent, conversation_id}, _from, state) do
    state = roll_day(state)
    {:reply, Map.get(state.per_conversation, conversation_id, 0), state}
  end

  def handle_call(:global_spent, _from, state) do
    state = roll_day(state)
    {:reply, state.global, state}
  end

  @impl true
  def handle_cast({:record, conversation_id, tokens}, state) do
    new_state =
      state
      |> roll_day()
      |> update_in([Access.key(:per_conversation), conversation_id], &((&1 || 0) + tokens))
      |> Map.update!(:global, &(&1 + tokens))

    {:noreply, new_state}
  end

  # Daily caps: when the current day differs from the stored day, zero the
  # counters before serving the request. This makes "daily" real — the cap
  # self-heals at the UTC-day rollover (or whatever `day_fun` reports) instead
  # of being a permanent process-lifetime ceiling.
  defp roll_day(state) do
    case state.day_fun.() do
      same when same == state.day -> state
      new_day -> %{state | day: new_day, per_conversation: %{}, global: 0}
    end
  end

  # A cap is reached when spend meets or exceeds it. :infinity is never over.
  defp over?(_spent, :infinity), do: false
  defp over?(spent, cap), do: spent >= cap

  defp usage_tokens({:ok, %{usage: usage}}) when is_map(usage) do
    Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0)
  end

  defp usage_tokens(_), do: 0
end
