defmodule Virtuoso.Ensemble.Strategy.QuorumTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Ensemble.Strategy.Quorum

  describe "aggregate/2 — first K agreeing" do
    test "reaches consensus as soon as K members agree" do
      votes = ["a", "b", "a", "a"]
      assert {:consensus, "a", meta} = Quorum.aggregate(votes, k: 3)
      assert meta.count == 3
    end

    test "canonicalizes so equivalent structured values count toward K" do
      votes = [%{x: 1, y: 2}, %{y: 2, x: 1}]
      assert {:consensus, %{x: 1, y: 2}, _} = Quorum.aggregate(votes, k: 2)
    end

    test "no value reaches K → no consensus" do
      votes = ["a", "b", "c"]
      assert {:no_consensus, :quorum_not_reached, _} = Quorum.aggregate(votes, k: 2)
    end

    test "k defaults to a strict majority of the votes when unspecified" do
      # 3 of 5 = majority
      votes = ["a", "a", "a", "b", "c"]
      assert {:consensus, "a", _} = Quorum.aggregate(votes, [])
    end

    test "empty votes is no consensus" do
      assert {:no_consensus, :no_votes, _} = Quorum.aggregate([], k: 1)
    end
  end
end
