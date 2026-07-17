defmodule Virtuoso.Ensemble.CheckerTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Ensemble.Checker

  # maker: (tier -> candidate). We use an Agent to script a sequence of
  # accept/reject decisions and to observe which tier the maker was called at.
  defp scripted(verdicts) do
    {:ok, agent} = Agent.start_link(fn -> {verdicts, []} end)
    agent
  end

  defp maker_fn(agent) do
    fn tier ->
      Agent.update(agent, fn {v, tiers} -> {v, [tier | tiers]} end)
      %{text: "candidate", tier: tier}
    end
  end

  defp checker_fn(agent) do
    fn _candidate ->
      Agent.get_and_update(agent, fn {[verdict | rest], tiers} -> {verdict, {rest, tiers}} end)
    end
  end

  defp tiers_called(agent), do: Agent.get(agent, fn {_v, tiers} -> Enum.reverse(tiers) end)

  @tiers ["haiku", "opus"]

  describe "run/1" do
    test "accepts on the first try" do
      agent = scripted([:accept])

      assert {:ok, candidate, meta} =
               Checker.run(
                 maker: maker_fn(agent),
                 checker: checker_fn(agent),
                 tiers: @tiers
               )

      assert candidate.text == "candidate"
      assert meta.attempts == 1
      assert meta.escalated == false
      assert tiers_called(agent) == ["haiku"]
    end

    test "one rejection then accept, no escalation" do
      agent = scripted([:reject, :accept])

      assert {:ok, _candidate, meta} =
               Checker.run(maker: maker_fn(agent), checker: checker_fn(agent), tiers: @tiers)

      assert meta.attempts == 2
      assert meta.rejections == 1
      assert meta.escalated == false
      # both attempts at the base tier (escalation only after 2 rejections)
      assert tiers_called(agent) == ["haiku", "haiku"]
    end

    test "two rejections escalate one tier once, then accept" do
      agent = scripted([:reject, :reject, :accept])

      assert {:ok, _candidate, meta} =
               Checker.run(maker: maker_fn(agent), checker: checker_fn(agent), tiers: @tiers)

      assert meta.rejections == 2
      assert meta.escalated == true
      # base, base, then escalated tier
      assert tiers_called(agent) == ["haiku", "haiku", "opus"]
    end

    test "exhaustion after escalation → best-effort, flagged" do
      # reject, reject (escalate), reject again → give up
      agent = scripted([:reject, :reject, :reject])

      assert {:flagged, candidate, meta} =
               Checker.run(maker: maker_fn(agent), checker: checker_fn(agent), tiers: @tiers)

      assert candidate.text == "candidate"
      assert meta.escalated == true
      assert meta.reason == :checker_exhausted
      # never regenerates unbounded: base, base, escalated — exactly 3 makes
      assert tiers_called(agent) == ["haiku", "haiku", "opus"]
    end

    test "escalation is capped even without a higher tier available" do
      # single-tier: 2 rejections, no tier to escalate to → give up after the bound
      agent = scripted([:reject, :reject, :reject])

      assert {:flagged, _candidate, meta} =
               Checker.run(maker: maker_fn(agent), checker: checker_fn(agent), tiers: ["only"])

      assert meta.reason == :checker_exhausted
      # bounded: no infinite loop even with no tier to escalate to
      assert length(tiers_called(agent)) <= 3
    end
  end
end
