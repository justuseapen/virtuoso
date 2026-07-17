defmodule Virtuoso.Ensemble.Checker do
  @moduledoc """
  Bounded maker/checker verification (plan decision 6).

  A *maker* produces a candidate; a *checker* accepts or rejects it. The loop is
  strictly bounded to keep cost finite — it never regenerates indefinitely:

    1. Make a candidate at the base tier; if the checker accepts, done.
    2. On rejection, retry at the base tier (up to `max_rejections`, default 2).
    3. After `max_rejections` at the base tier, **escalate one model tier once**
       and make one more candidate.
    4. If the escalated candidate is still rejected, return the best-effort
       candidate **flagged** (`{:flagged, candidate, meta}`) rather than looping.

  Worst case is `max_rejections + 1` maker calls (e.g. base, base, escalated).

  ## Options
    * `:maker` — `(tier -> candidate)`; required. Produces a candidate at a tier.
    * `:checker` — `(candidate -> :accept | :reject)`; required.
    * `:tiers` — model tiers cheapest-first, e.g. `["haiku", "opus"]`; required.
      Escalation moves to the next tier; if there is none, the bound still holds.
    * `:max_rejections` — rejections at the base tier before escalating (default 2).

  ## Returns
    * `{:ok, candidate, meta}` — the checker accepted.
    * `{:flagged, candidate, meta}` — bound exhausted; best-effort, flagged.
  """

  @default_max_rejections 2

  @type candidate :: term()
  @type result :: {:ok, candidate(), map()} | {:flagged, candidate(), map()}

  @spec run(keyword()) :: result()
  def run(opts) do
    maker = Keyword.fetch!(opts, :maker)
    checker = Keyword.fetch!(opts, :checker)
    tiers = Keyword.fetch!(opts, :tiers)
    max_rejections = Keyword.get(opts, :max_rejections, @default_max_rejections)

    [base | rest] = tiers

    loop(
      maker,
      checker,
      base,
      rest,
      max_rejections,
      _rejections = 0,
      _escalated = false,
      _attempts = 0
    )
  end

  # Base-tier attempts until acceptance or max_rejections; then escalate once.
  defp loop(maker, checker, tier, rest, max_rejections, rejections, escalated, attempts) do
    candidate = maker.(tier)
    attempts = attempts + 1

    case checker.(candidate) do
      :accept ->
        {:ok, candidate, meta(attempts, rejections, escalated)}

      :reject ->
        on_reject(maker, checker, tier, rest, max_rejections, rejections + 1, escalated, attempts)
    end
  end

  # Under the base-tier bound → retry same tier. At the bound → escalate one tier
  # once (or, with no higher tier, one more attempt at this tier). `loop/8` only
  # runs base-tier attempts (escalated: false), so there is no third branch — the
  # escalated terminal case is handled entirely inside escalate/5.
  defp on_reject(maker, checker, tier, rest, max_rejections, rejections, escalated, attempts) do
    if rejections < max_rejections do
      loop(maker, checker, tier, rest, max_rejections, rejections, escalated, attempts)
    else
      escalate(maker, checker, next_tier(rest, tier), rejections, attempts)
    end
  end

  defp next_tier([next | _], _current), do: next
  defp next_tier([], current), do: current

  # One escalated attempt. Accept → ok; reject → flagged (never loop further).
  defp escalate(maker, checker, tier, rejections, attempts) do
    candidate = maker.(tier)
    attempts = attempts + 1

    case checker.(candidate) do
      :accept -> {:ok, candidate, meta(attempts, rejections, true)}
      :reject -> flagged(candidate, attempts, rejections + 1, true)
    end
  end

  defp flagged(candidate, attempts, rejections, escalated) do
    meta = Map.put(meta(attempts, rejections, escalated), :reason, :checker_exhausted)
    {:flagged, candidate, meta}
  end

  defp meta(attempts, rejections, escalated) do
    %{attempts: attempts, rejections: rejections, escalated: escalated}
  end
end
