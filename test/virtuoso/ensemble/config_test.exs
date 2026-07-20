defmodule Virtuoso.Ensemble.ConfigTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Ensemble.Config
  alias Virtuoso.Ensemble.Strategy.{Judge, Majority, Quorum}

  describe "resolve/1 — defaults and strategy mapping" do
    test "supplies sane defaults" do
      c = Config.resolve([])
      assert c.n == 3
      assert c.strategy == Majority
      assert c.models == []
      assert c.strategy_opts == []
    end

    test "maps atom strategy names to modules" do
      assert Config.resolve(strategy: :majority).strategy == Majority
      assert Config.resolve(strategy: :quorum).strategy == Quorum
      assert Config.resolve(strategy: :judge).strategy == Judge
    end

    test "accepts a strategy module directly" do
      assert Config.resolve(strategy: Quorum).strategy == Quorum
    end

    test "carries n, models, and strategy_opts through" do
      c = Config.resolve(n: 5, models: ["a", "b"], strategy_opts: [k: 3])
      assert c.n == 5
      assert c.models == ["a", "b"]
      assert c.strategy_opts == [k: 3]
    end

    test "raises on an unknown strategy name" do
      assert_raise ArgumentError, ~r/unknown strategy/, fn ->
        Config.resolve(strategy: :nonsense)
      end
    end
  end

  describe "merge/2 — per-bot defaults + per-routine override" do
    test "an empty override yields the bot defaults" do
      defaults = [n: 5, strategy: :quorum]
      assert Config.merge(defaults, []).n == 5
      assert Config.merge(defaults, []).strategy == Quorum
    end

    test "the routine override wins field-by-field" do
      defaults = [n: 3, strategy: :majority, models: ["x"]]
      override = [n: 7, strategy: :judge]

      merged = Config.merge(defaults, override)
      assert merged.n == 7
      assert merged.strategy == Judge
      # models not overridden → inherited from defaults
      assert merged.models == ["x"]
    end

    test "override can be nil (no per-routine config)" do
      assert Config.merge([n: 9], nil).n == 9
    end
  end

  describe "to_ensemble_opts/1" do
    test "produces the keyword shape Slow/Ensemble expect" do
      opts =
        Config.resolve(n: 4, strategy: :quorum, strategy_opts: [k: 2])
        |> Config.to_ensemble_opts()

      assert opts[:n] == 4
      assert opts[:strategy] == Quorum
      assert opts[:strategy_opts] == [k: 2]
    end
  end
end
