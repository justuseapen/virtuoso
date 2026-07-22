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
    * `:telemetry_meta` — map merged into run start/stop telemetry metadata
      (e.g. `%{conversation_id: id}`); reserved keys always win on conflict.

  ## Returns
    * `{:consensus, decision, meta}` — the strategy committed a decision.
    * `{:fallback, decision, meta}` — no consensus; a single survivor's decision.
    * `{:error, :all_members_failed, meta}` — no member produced a decision.

  `meta` always carries `members_total`/`members_ok`/`members_dropped` and
  `usage` (token totals summed across surviving members — the cost of the
  decision).

  ## Telemetry (public API — versioned from 0.1.0)

    * `[:virtuoso, :ensemble, :run, :start]` — measurements `%{system_time}`,
      metadata `%{strategy, members_total}`.
    * `[:virtuoso, :ensemble, :run, :stop]` — measurements `%{duration}`,
      metadata `%{strategy, outcome: :consensus | :fallback | :error, decision,
      members_total, members_ok, members_dropped, usage}` plus the strategy's
      meta (`:count` = agreeing members, so dissent = `members_ok - count`;
      `:reason` on fallback/error). This is the dashboard's feed: votes,
      dissent, latency, and cost per decision.

  Both events' metadata also include any caller-supplied `:telemetry_meta` keys.
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
    telemetry_meta = opts |> Keyword.get(:telemetry_meta, %{}) |> Map.new()

    total = length(members)
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:virtuoso, :ensemble, :run, :start],
      %{system_time: System.system_time()},
      Map.merge(telemetry_meta, %{strategy: strategy, members_total: total})
    )

    survivors = fan_out(base_request, members, extract, llm, timeout)
    decisions = Enum.map(survivors, &elem(&1, 0))
    ok = length(decisions)

    base_meta = %{
      members_total: total,
      members_ok: ok,
      members_dropped: total - ok,
      usage: total_usage(survivors)
    }

    result =
      if ok == 0 do
        {:error, :all_members_failed, base_meta}
      else
        aggregate(strategy, decisions, strategy_opts, base_meta)
      end

    :telemetry.execute(
      [:virtuoso, :ensemble, :run, :stop],
      %{duration: System.monotonic_time() - start_time},
      stop_metadata(strategy, result, telemetry_meta)
    )

    result
  end

  # Fan out members concurrently; keep only the ones that produced a decision
  # (paired with their token usage — the dashboard's cost-per-decision feed).
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
      {:ok, {:ok, decision, usage}} -> [{decision, usage}]
      _ -> []
    end)
  end

  defp run_member(base_request, member, extract, llm, timeout) do
    request = Map.merge(base_request, member)

    case llm.(request, timeout: timeout) do
      {:ok, completion} ->
        case extract.(completion) do
          {:ok, decision} -> {:ok, decision, Map.get(completion, :usage, %{})}
          :error -> :error
        end

      {:error, _reason} ->
        :error
    end
  end

  defp total_usage(survivors) do
    Enum.reduce(survivors, %{input_tokens: 0, output_tokens: 0}, fn {_d, usage}, acc ->
      %{
        input_tokens: acc.input_tokens + Map.get(usage, :input_tokens, 0),
        output_tokens: acc.output_tokens + Map.get(usage, :output_tokens, 0)
      }
    end)
  end

  ## Telemetry (public API — versioned from 0.1.0)
  #
  #   [:virtuoso, :ensemble, :run, :start] — %{system_time};
  #     meta %{strategy, members_total}
  #   [:virtuoso, :ensemble, :run, :stop]  — %{duration};
  #     meta %{strategy, outcome: :consensus | :fallback | :error, decision,
  #            members_total, members_ok, members_dropped, usage, ...strategy meta
  #            (:count for agreement — dissent = members_ok - count, :reason on
  #            fallback/error)}
  #   Both events also merge in caller-supplied :telemetry_meta keys (reserved
  #   keys above always win on conflict).
  defp stop_metadata(strategy, {outcome, decision_or_reason, meta}, telemetry_meta) do
    base = telemetry_meta |> Map.merge(meta) |> Map.merge(%{strategy: strategy})

    case outcome do
      :consensus -> Map.merge(base, %{outcome: :consensus, decision: decision_or_reason})
      :fallback -> Map.merge(base, %{outcome: :fallback, decision: decision_or_reason})
      :error -> Map.merge(base, %{outcome: :error, decision: nil, reason: decision_or_reason})
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
