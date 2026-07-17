defmodule Virtuoso.Ensemble.Strategy.Majority do
  @moduledoc """
  Majority consensus: the value with the most (canonicalized) votes wins,
  provided it clears the agreement bar.

  By default the bar is a **strict majority** (more than half), so a tie or a
  plurality-below-half is `:no_consensus` and the ensemble falls back to a
  single model. Lower the bar with `min_agreement: n` to accept a plurality of
  at least `n`.
  """

  @behaviour Virtuoso.Ensemble.Strategy

  alias Virtuoso.Ensemble.Strategy

  @impl true
  def aggregate([], _opts), do: {:no_consensus, :no_votes, %{total: 0}}

  def aggregate(votes, opts) do
    total = length(votes)
    tally = Strategy.tally(votes)
    {_key, {top_value, top_count}} = Enum.max_by(tally, fn {_k, {_v, c}} -> c end)

    threshold = Keyword.get(opts, :min_agreement, div(total, 2) + 1)
    tied = tied_top(tally, top_count)

    cond do
      length(tied) > 1 and top_count >= threshold ->
        {:no_consensus, :tie, %{total: total, count: top_count, top_tied: tied}}

      top_count >= threshold ->
        {:consensus, top_value, %{total: total, count: top_count}}

      length(tied) > 1 ->
        {:no_consensus, :tie, %{total: total, count: top_count, top_tied: tied}}

      true ->
        {:no_consensus, :no_majority, %{total: total, count: top_count}}
    end
  end

  # The representative values sharing the top count (to report a tie).
  defp tied_top(tally, top_count) do
    tally
    |> Enum.filter(fn {_k, {_v, c}} -> c == top_count end)
    |> Enum.map(fn {_k, {v, _c}} -> v end)
  end
end
