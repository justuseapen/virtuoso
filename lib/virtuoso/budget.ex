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

  Every LLM call passes `check/2` first; on refusal the framework short-circuits
  to a defined fallback response (`refusal_message/0`) instead of spending. The
  N-members-×-judge-×-checker cost multiplier is structural, so this gate exists
  from Phase 1.

  `with_budget/3` is the intended call site: it gates, runs the LLM call only if
  permitted, records actual usage from the result, and returns the fallback tuple
  when over budget — so callers can't forget to record spend.
  """

  use GenServer

  @refusal_message "I've reached my usage limit for now. Please try again later."

  @type name :: atom() | pid()
  @type check_result :: :ok | {:error, :budget_exceeded | :killed}

  defstruct per_conversation_daily: :infinity,
            global_daily: :infinity,
            kill_switch: false,
            per_conversation: %{},
            global: 0

  # --- public API -----------------------------------------------------------

  @doc """
  Start a budget process.

  Options: `:name`, `:per_conversation_daily`, `:global_daily` (token counts or
  `:infinity`), `:kill_switch` (boolean).
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
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
  def check(server \\ __MODULE__, conversation_id) do
    GenServer.call(server, {:check, conversation_id})
  end

  @doc "Record `tokens` spent by `conversation_id` against both caps."
  @spec record(name(), String.t(), non_neg_integer()) :: :ok
  def record(server \\ __MODULE__, conversation_id, tokens) do
    GenServer.call(server, {:record, conversation_id, tokens})
  end

  @doc "Engage or release the global kill switch."
  @spec kill_switch(name(), boolean()) :: :ok
  def kill_switch(server \\ __MODULE__, engaged?) do
    GenServer.call(server, {:kill_switch, engaged?})
  end

  @doc "Tokens spent by a conversation today."
  @spec spent(name(), String.t()) :: non_neg_integer()
  def spent(server \\ __MODULE__, conversation_id) do
    GenServer.call(server, {:spent, conversation_id})
  end

  @doc "Total tokens spent across all conversations today."
  @spec global_spent(name()) :: non_neg_integer()
  def global_spent(server \\ __MODULE__) do
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
  def with_budget(server \\ __MODULE__, conversation_id, fun) do
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
    state = %__MODULE__{
      per_conversation_daily: Keyword.get(opts, :per_conversation_daily, :infinity),
      global_daily: Keyword.get(opts, :global_daily, :infinity),
      kill_switch: Keyword.get(opts, :kill_switch, false)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:check, _conversation_id}, _from, %{kill_switch: true} = state) do
    {:reply, {:error, :killed}, state}
  end

  def handle_call({:check, conversation_id}, _from, state) do
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

  def handle_call({:record, conversation_id, tokens}, _from, state) do
    new_state =
      state
      |> update_in([Access.key(:per_conversation), conversation_id], &((&1 || 0) + tokens))
      |> Map.update!(:global, &(&1 + tokens))

    {:reply, :ok, new_state}
  end

  def handle_call({:kill_switch, engaged?}, _from, state) do
    {:reply, :ok, %{state | kill_switch: engaged?}}
  end

  def handle_call({:spent, conversation_id}, _from, state) do
    {:reply, Map.get(state.per_conversation, conversation_id, 0), state}
  end

  def handle_call(:global_spent, _from, state) do
    {:reply, state.global, state}
  end

  # A cap is reached when spend meets or exceeds it. :infinity is never over.
  defp over?(_spent, :infinity), do: false
  defp over?(spent, cap), do: spent >= cap

  defp usage_tokens({:ok, %{usage: usage}}) when is_map(usage) do
    Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0)
  end

  defp usage_tokens(_), do: 0
end
