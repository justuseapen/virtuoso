defmodule Virtuoso.Ensemble.Strategy.Quorum do
  @moduledoc """
  K-of-N quorum: the first value to reach `k` (canonicalized) agreeing votes
  wins.

  Distinct from `Majority` in intent: quorum answers "did at least K members
  agree?" rather than "which value won the plurality?". `k` defaults to a strict
  majority of the votes cast.
  """

  @behaviour Virtuoso.Ensemble.Strategy

  alias Virtuoso.Ensemble.Strategy

  @impl true
  def aggregate([], _opts), do: {:no_consensus, :no_votes, %{total: 0}}

  def aggregate(votes, opts) do
    total = length(votes)
    k = Keyword.get(opts, :k, div(total, 2) + 1)
    tally = Strategy.tally(votes)
    {_key, {top_value, top_count}} = Enum.max_by(tally, fn {_k, {_v, c}} -> c end)

    if top_count >= k do
      {:consensus, top_value, %{total: total, count: top_count, k: k}}
    else
      {:no_consensus, :quorum_not_reached, %{total: total, count: top_count, k: k}}
    end
  end
end
