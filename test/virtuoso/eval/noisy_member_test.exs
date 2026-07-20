defmodule Virtuoso.Eval.NoisyMemberTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Eval.{NoisyMember, Task}

  @task %Task{
    id: "t1",
    prompt: "route this",
    answer: "route_a",
    distractors: ["route_b", "route_c", "route_d"]
  }

  describe "respond/3" do
    test "returns the correct answer when error_rate is 0" do
      for member <- 1..10 do
        assert NoisyMember.respond(@task, member, error_rate: 0.0, seed: 1) == "route_a"
      end
    end

    test "returns only distractors when error_rate is 1.0 (never the answer)" do
      for member <- 1..20 do
        answer = NoisyMember.respond(@task, member, error_rate: 1.0, seed: 1)
        assert answer in @task.distractors
        refute answer == @task.answer
      end
    end

    test "is deterministic for the same (task, member, seed)" do
      a = NoisyMember.respond(@task, 3, error_rate: 0.3, seed: 42)
      b = NoisyMember.respond(@task, 3, error_rate: 0.3, seed: 42)
      assert a == b
    end

    test "different members diverge (independent errors), enabling correction" do
      # At a high error rate, different members should not all give the same
      # wrong answer — that independence is what lets majority voting recover.
      answers =
        for member <- 1..12, do: NoisyMember.respond(@task, member, error_rate: 0.6, seed: 7)

      assert length(Enum.uniq(answers)) > 1
    end

    test "empirical error rate is close to the configured rate over many members" do
      n = 400

      wrong =
        Enum.count(1..n, fn m ->
          NoisyMember.respond(@task, m, error_rate: 0.25, seed: 99) != @task.answer
        end)

      observed = wrong / n
      # within a reasonable band of the configured 0.25
      assert_in_delta observed, 0.25, 0.08
    end
  end

  describe "as an ensemble llm fn" do
    test "llm_fun/2 produces a completion whose text is the member's answer" do
      llm = NoisyMember.llm_fun(@task, error_rate: 0.0, seed: 1)
      # request carries the member index under :member (set by the runner)
      assert {:ok, %{text: "route_a"}} = llm.(%{model: "m", member: 5}, [])
    end
  end
end
