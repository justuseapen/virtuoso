defmodule Virtuoso.Eval.Task do
  @moduledoc """
  One eval task with a known-correct answer.

  Used by the eval harness to measure accuracy: a task has a single correct
  `answer` and a set of plausible `distractors` a noisy member might return
  instead. Categorical by construction — the domain where consensus is sound
  (routing, tool selection, extraction verdicts), per the plan's decision 1.
  """

  @enforce_keys [:id, :prompt, :answer, :distractors]
  defstruct [:id, :prompt, :answer, :distractors]

  @type t :: %__MODULE__{
          id: String.t(),
          prompt: String.t(),
          answer: String.t(),
          distractors: [String.t()]
        }
end
