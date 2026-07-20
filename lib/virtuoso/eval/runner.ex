defmodule Virtuoso.Eval.Runner do
  @moduledoc """
  The eval harness: does N-way consensus actually beat a single call?

  For each task, the runner measures two strategies against the known answer:

    * **single-call** — one member's answer (the baseline).
    * **ensemble** — `Virtuoso.Ensemble.run/3` with N noisy members voting by
      majority; the committed (or fallback) decision.

  Members err independently (`Virtuoso.Eval.NoisyMember`), so majority-of-N
  corrects the single call's mistakes — the mechanism the flagship rests on. The
  report includes both accuracies and the token multiplier (N), so the accuracy
  gain can be weighed against the cost.

  This runs fully offline and deterministically (seeded), so the claim
  "consensus beats single-call" is reproducible in CI, not a one-off measurement
  against a live model.
  """

  alias Virtuoso.Ensemble
  alias Virtuoso.Ensemble.Strategy.Majority
  alias Virtuoso.Eval.{NoisyMember, Task}

  @type report :: %{
          tasks: non_neg_integer(),
          n: pos_integer(),
          error_rate: float(),
          single_accuracy: float(),
          ensemble_accuracy: float(),
          token_multiplier: float()
        }

  @doc """
  Run the task set single-call vs. ensemble and report accuracies.

  Options: `:n` (members, default 5), `:error_rate` (per-member, default 0.3),
  `:seed` (default 0).
  """
  @spec run([Task.t()], keyword()) :: report()
  def run(tasks, opts \\ []) do
    n = Keyword.get(opts, :n, 5)
    error_rate = Keyword.get(opts, :error_rate, 0.3)
    seed = Keyword.get(opts, :seed, 0)

    member_opts = [error_rate: error_rate, seed: seed]

    single_correct = Enum.count(tasks, &single_correct?(&1, member_opts))
    ensemble_correct = Enum.count(tasks, &ensemble_correct?(&1, n, member_opts))
    total = length(tasks)

    %{
      tasks: total,
      n: n,
      error_rate: error_rate,
      single_accuracy: accuracy(single_correct, total),
      ensemble_accuracy: accuracy(ensemble_correct, total),
      token_multiplier: n / 1
    }
  end

  # Single-call baseline: member 1's answer.
  defp single_correct?(%Task{} = task, member_opts) do
    NoisyMember.respond(task, 1, member_opts) == task.answer
  end

  # Ensemble: N members vote by majority; correct if the committed/fallback
  # decision matches the answer.
  defp ensemble_correct?(%Task{} = task, n, member_opts) do
    members = for i <- 1..n, do: %{model: "noisy", member: i}
    llm = NoisyMember.llm_fun(task, member_opts)

    opts = [
      members: members,
      strategy: Majority,
      extract: fn %{text: text} -> {:ok, text} end,
      llm: llm
    ]

    decision =
      case Ensemble.run(%{messages: [%{role: :user, content: task.prompt}]}, opts) do
        {:consensus, d, _} -> d
        {:fallback, d, _} -> d
        {:error, _, _} -> nil
      end

    decision == task.answer
  end

  defp accuracy(_correct, 0), do: 0.0
  defp accuracy(correct, total), do: correct / total
end
