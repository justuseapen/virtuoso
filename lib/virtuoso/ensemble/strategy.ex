defmodule Virtuoso.Ensemble.Strategy do
  @moduledoc """
  The behaviour a consensus strategy implements, plus shared canonicalization.

  A strategy aggregates the **structured/categorical** outputs of ensemble
  members into a single committed decision. Per the plan's decision 1, consensus
  applies only where equivalence is a canonicalized exact match — routing
  decisions, tool selection, JSON-schema extraction, pass/fail verdicts. Free-form
  generative text is never voted on; it uses single-model generation.

  `aggregate/2` takes the list of member outputs (already extracted decisions,
  not raw completions) and options, and returns:

    * `{:consensus, decision, meta}` — the committed decision + metadata (counts).
    * `{:no_consensus, reason, meta}` — no decision; the caller falls back
      (single-model) per the ensemble's partial-failure policy.

  Ships with `Majority`, `Quorum`, and `Judge`.
  """

  @type vote :: term()
  @type decision :: term()
  @type meta :: map()
  @type result ::
          {:consensus, decision(), meta()} | {:no_consensus, atom(), meta()}

  @doc "Aggregate member votes into a committed decision or a no-consensus result."
  @callback aggregate([vote()], keyword()) :: result()

  @doc """
  A canonical, order-independent key for a structured value.

  Maps are sorted by key (recursively) before encoding so `%{a: 1, b: 2}` and
  `%{b: 2, a: 1}` collapse to the same vote. Lists keep order (order can be
  meaningful). The result is an opaque binary used only for grouping.
  """
  @spec canonical(term()) :: binary()
  def canonical(value), do: value |> canonicalize() |> :erlang.term_to_binary()

  defp canonicalize(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {canonicalize(k), canonicalize(v)} end)
    |> Enum.sort()
  end

  defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
  defp canonicalize(value) when is_binary(value), do: String.trim(value)
  defp canonicalize(value), do: value

  @doc """
  Tally votes by canonical key, returning `%{canonical_key => {representative, count}}`.

  The representative is the first original value seen for that key, so the
  returned decision is a real member value (not the canonicalized form).
  """
  @spec tally([vote()]) :: %{binary() => {vote(), pos_integer()}}
  def tally(votes) do
    Enum.reduce(votes, %{}, fn vote, acc ->
      key = canonical(vote)

      Map.update(acc, key, {vote, 1}, fn {rep, count} -> {rep, count + 1} end)
    end)
  end
end
