defmodule Virtuoso.Ensemble do
  @moduledoc """
  Actor-based parallel consensus — the framework's flagship.

  `run/3` fans out N **member** variants of a request (different model,
  temperature, or prompt) as concurrent tasks, extracts a structured decision
  from each, and aggregates the survivors with a `Virtuoso.Ensemble.Strategy`.
  This is the "many lightweight processes reason concurrently, aggregate by
  consensus" idea made concrete.

  Invariants (from the plan's design decisions):

    * **Members are pure** (decision 2). A member runs an LLM call and extracts a
      *decision*; it performs no tool side effects. N members must never mean N
      side effects — tools run only after consensus commits.
    * **Consensus is for structured decisions** (decision 1). The `:extract`
      function pulls a categorical/structured value (a route, a tool name, a
      JSON object, a verdict) from each completion; equivalence is the strategy's
      canonicalized match. Free-form generation does not come through here.
    * **Partial failure is expected.** Members that error (429/timeout/overload)
      or fail extraction are dropped; the strategy votes among survivors. Below
      consensus, the ensemble falls back to a single member's decision rather
      than failing the turn.

  ## Options
    * `:members` — list of request-override maps (each merged onto the base request).
    * `:strategy` — a `Strategy` module (default `Majority`).
    * `:strategy_opts` — options passed to the strategy's `aggregate/2`.
    * `:extract` — `(completion -> {:ok, decision} | :error)`; required.
    * `:llm` — `(request, opts -> {:ok, completion} | {:error, Error.t()})`;
      defaults to `&Virtuoso.LLM.complete/2`. The seam that keeps `run/3`
      testable and lets a caller gate members through the budget.
    * `:timeout` — per-member timeout (default 30s).

  ## Returns
    * `{:consensus, decision, meta}` — the strategy committed a decision.
    * `{:fallback, decision, meta}` — no consensus; a single survivor's decision.
    * `{:error, :all_members_failed, meta}` — no member produced a decision.
  """

  alias Virtuoso.Ensemble.Strategy
  alias Virtuoso.LLM

  @task_supervisor Virtuoso.Ensemble.TaskSupervisor
  @default_strategy Strategy.Majority

  @type member :: map()
  @type decision :: term()
  @type result ::
          {:consensus, decision(), map()}
          | {:fallback, decision(), map()}
          | {:error, :all_members_failed, map()}

  @spec run(map(), keyword()) :: result()
  def run(base_request, opts) do
    members = Keyword.fetch!(opts, :members)
    strategy = Keyword.get(opts, :strategy, @default_strategy)
    strategy_opts = Keyword.get(opts, :strategy_opts, [])
    extract = Keyword.fetch!(opts, :extract)
    llm = Keyword.get(opts, :llm, &LLM.complete/2)
    timeout = Keyword.get(opts, :timeout, 30_000)

    total = length(members)
    decisions = fan_out(base_request, members, extract, llm, timeout)
    ok = length(decisions)
    dropped = total - ok

    base_meta = %{members_total: total, members_ok: ok, members_dropped: dropped}

    if ok == 0 do
      {:error, :all_members_failed, base_meta}
    else
      aggregate(strategy, decisions, strategy_opts, base_meta)
    end
  end

  # Fan out members concurrently; keep only the ones that produced a decision.
  # async_stream_nolink so a crashing member never takes down the caller — a
  # crash/exit becomes a dropped member, exactly like a 429.
  defp fan_out(base_request, members, extract, llm, timeout) do
    @task_supervisor
    |> Task.Supervisor.async_stream_nolink(
      members,
      fn member -> run_member(base_request, member, extract, llm, timeout) end,
      timeout: timeout + 1_000,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, decision}} -> [decision]
      _ -> []
    end)
  end

  defp run_member(base_request, member, extract, llm, timeout) do
    request = Map.merge(base_request, member)

    case llm.(request, timeout: timeout) do
      {:ok, completion} -> extract.(completion)
      {:error, _reason} -> :error
    end
  end

  defp aggregate(strategy, decisions, strategy_opts, base_meta) do
    case strategy.aggregate(decisions, strategy_opts) do
      {:consensus, decision, meta} ->
        {:consensus, decision, Map.merge(base_meta, meta)}

      {:no_consensus, reason, meta} ->
        # Fall back to a single survivor's decision rather than failing the turn.
        {:fallback, hd(decisions), base_meta |> Map.merge(meta) |> Map.put(:reason, reason)}
    end
  end
end
