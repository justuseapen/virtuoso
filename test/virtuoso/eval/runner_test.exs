defmodule Virtuoso.Eval.RunnerTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Eval.{Runner, Task}

  # A small routing/extraction task set with known answers.
  defp task_set do
    [
      %Task{
        id: "r1",
        prompt: "book a flight",
        answer: "book",
        distractors: ["cancel", "change", "refund"]
      },
      %Task{
        id: "r2",
        prompt: "cancel my order",
        answer: "cancel",
        distractors: ["book", "change", "refund"]
      },
      %Task{
        id: "r3",
        prompt: "change seat",
        answer: "change",
        distractors: ["book", "cancel", "refund"]
      },
      %Task{
        id: "r4",
        prompt: "get a refund",
        answer: "refund",
        distractors: ["book", "cancel", "change"]
      },
      %Task{
        id: "r5",
        prompt: "book again",
        answer: "book",
        distractors: ["cancel", "change", "refund"]
      },
      %Task{
        id: "r6",
        prompt: "cancel again",
        answer: "cancel",
        distractors: ["book", "change", "refund"]
      }
    ]
  end

  describe "run/2" do
    test "reports single-call and ensemble accuracy plus the token multiplier" do
      report = Runner.run(task_set(), n: 5, error_rate: 0.3, seed: 1)

      assert report.tasks == 6
      assert report.n == 5
      assert is_float(report.single_accuracy)
      assert is_float(report.ensemble_accuracy)
      assert report.token_multiplier == 5.0
    end

    test "ensemble accuracy measurably beats single-call at a realistic error rate" do
      # Independent errors + majority-of-5 should correct the single-call noise.
      report = Runner.run(task_set(), n: 5, error_rate: 0.35, seed: 1)

      assert report.ensemble_accuracy > report.single_accuracy,
             "expected ensemble #{report.ensemble_accuracy} > single #{report.single_accuracy}"
    end

    test "the accuracy gain holds across several seeds (not a lucky seed)" do
      gains =
        for seed <- 1..8 do
          r = Runner.run(task_set(), n: 5, error_rate: 0.35, seed: seed)
          r.ensemble_accuracy - r.single_accuracy
        end

      # Ensemble should win on average; allow an occasional tie on a tiny task set.
      avg_gain = Enum.sum(gains) / length(gains)
      assert avg_gain > 0.0, "expected positive average gain, got #{avg_gain}"
      assert Enum.count(gains, &(&1 >= 0)) >= 6
    end

    test "is deterministic for a fixed seed" do
      a = Runner.run(task_set(), n: 5, error_rate: 0.3, seed: 42)
      b = Runner.run(task_set(), n: 5, error_rate: 0.3, seed: 42)
      assert a == b
    end

    test "with zero error, both are perfect and the gain is zero" do
      report = Runner.run(task_set(), n: 5, error_rate: 0.0, seed: 1)
      assert report.single_accuracy == 1.0
      assert report.ensemble_accuracy == 1.0
    end
  end
end
