defmodule Virtuoso.Ensemble.Strategy.MajorityTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Ensemble.Strategy.Majority

  describe "aggregate/2 — categorical outputs" do
    test "picks the strict-majority value" do
      votes = ["route_a", "route_a", "route_b"]
      assert {:consensus, "route_a", meta} = Majority.aggregate(votes, [])
      assert meta.count == 2
      assert meta.total == 3
    end

    test "canonicalizes maps so key order doesn't split the vote" do
      votes = [
        %{action: "book", qty: 2},
        %{qty: 2, action: "book"},
        %{action: "cancel", qty: 1}
      ]

      assert {:consensus, decision, meta} = Majority.aggregate(votes, [])
      assert decision == %{action: "book", qty: 2}
      assert meta.count == 2
    end

    test "requires a strict majority by default — a tie is no consensus" do
      votes = ["a", "a", "b", "b"]
      assert {:no_consensus, :tie, meta} = Majority.aggregate(votes, [])
      assert meta.top_tied == ["a", "b"] or meta.top_tied == ["b", "a"]
    end

    test "a plurality below majority is no consensus by default" do
      # 2 of 5 is the top but not > half
      votes = ["a", "a", "b", "c", "d"]
      assert {:no_consensus, :no_majority, _meta} = Majority.aggregate(votes, [])
    end

    test "min_agreement option lowers the bar to a plurality" do
      votes = ["a", "a", "b", "c", "d"]
      assert {:consensus, "a", _} = Majority.aggregate(votes, min_agreement: 2)
    end

    test "an empty vote list is no consensus" do
      assert {:no_consensus, :no_votes, _} = Majority.aggregate([], [])
    end
  end

  test "implements the Strategy behaviour" do
    behaviours =
      Majority.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

    assert Virtuoso.Ensemble.Strategy in behaviours
  end
end
