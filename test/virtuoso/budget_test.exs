defmodule Virtuoso.BudgetTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Budget

  # Each test gets its own named budget process so they stay async-safe.
  setup context do
    name = :"budget_#{context.test}"

    start_supervised!(
      {Budget, name: name, per_conversation_daily: 100, global_daily: 250, kill_switch: false}
    )

    %{budget: name}
  end

  describe "check/2" do
    test "permits a conversation under both caps", %{budget: b} do
      assert :ok = Budget.check(b, "conv-1")
    end

    test "refuses when the per-conversation daily cap is exhausted", %{budget: b} do
      Budget.record(b, "conv-1", 100)
      assert {:error, :budget_exceeded} = Budget.check(b, "conv-1")
      # a different conversation is still fine
      assert :ok = Budget.check(b, "conv-2")
    end

    test "refuses when the global daily cap is exhausted", %{budget: b} do
      Budget.record(b, "conv-1", 100)
      Budget.record(b, "conv-2", 100)
      Budget.record(b, "conv-3", 60)
      # global now 260 > 250 — every conversation is refused
      assert {:error, :budget_exceeded} = Budget.check(b, "conv-4")
    end
  end

  describe "kill switch" do
    test "refuses all checks when engaged, and resumes when released", %{budget: b} do
      assert :ok = Budget.check(b, "conv-1")

      Budget.kill_switch(b, true)
      assert {:error, :killed} = Budget.check(b, "conv-1")

      Budget.kill_switch(b, false)
      assert :ok = Budget.check(b, "conv-1")
    end
  end

  describe "with_budget/3" do
    test "runs the function and records usage when permitted", %{budget: b} do
      result =
        Budget.with_budget(b, "conv-1", fn ->
          {:ok, %{usage: %{input_tokens: 10, output_tokens: 5}}}
        end)

      assert {:ok, _} = result
      assert Budget.spent(b, "conv-1") == 15
    end

    test "returns the refusal fallback without running the function when over budget", %{
      budget: b
    } do
      Budget.record(b, "conv-1", 100)

      ran? = fn -> send(self(), :ran) end

      result =
        Budget.with_budget(b, "conv-1", fn ->
          ran?.()
          {:ok, %{usage: %{input_tokens: 1, output_tokens: 1}}}
        end)

      assert result == {:refused, :budget_exceeded, Budget.refusal_message()}
      refute_received :ran
    end
  end

  describe "usage introspection" do
    test "reports per-conversation and global spend", %{budget: b} do
      Budget.record(b, "conv-1", 30)
      Budget.record(b, "conv-2", 20)
      assert Budget.spent(b, "conv-1") == 30
      assert Budget.spent(b, "conv-2") == 20
      assert Budget.global_spent(b) == 50
    end
  end

  describe "daily reset" do
    # Inject the "current day" so the rollover is deterministic. An Agent holds
    # the day the budget's clock function reads.
    setup do
      {:ok, clock} = Agent.start_link(fn -> ~D[2026-07-17] end)
      day_fun = fn -> Agent.get(clock, & &1) end
      name = :"budget_reset_#{System.unique_integer([:positive])}"

      start_supervised!(
        {Budget, name: name, per_conversation_daily: 100, global_daily: 250, day_fun: day_fun}
      )

      %{reset_budget: name, clock: clock}
    end

    test "counters reset when the day rolls over", %{reset_budget: b, clock: clock} do
      Budget.record(b, "conv-1", 100)
      assert {:error, :budget_exceeded} = Budget.check(b, "conv-1")
      assert Budget.spent(b, "conv-1") == 100

      # Advance to the next day — the cap should be fresh again.
      Agent.update(clock, fn _ -> ~D[2026-07-18] end)

      assert :ok = Budget.check(b, "conv-1")
      assert Budget.spent(b, "conv-1") == 0
      assert Budget.global_spent(b) == 0
    end

    test "spend within the same day still accumulates", %{reset_budget: b} do
      Budget.record(b, "conv-1", 40)
      Budget.record(b, "conv-1", 30)
      assert Budget.spent(b, "conv-1") == 70
    end
  end
end
