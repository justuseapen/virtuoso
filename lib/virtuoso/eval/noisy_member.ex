defmodule Virtuoso.Eval.NoisyMember do
  @moduledoc """
  A deterministic, stochastically-erring member for the offline eval harness.

  To *prove* that N-way consensus beats a single call, the harness needs members
  that are individually noisy but whose errors are **independent** — so a
  majority of N can correct the minority's mistakes (Condorcet's jury theorem).
  A real LLM is exactly such a member; this simulates one without the network so
  the proof is reproducible in CI.

  Given a task and a member index, `respond/3`:

    * returns the task's correct `answer` with probability `1 - error_rate`, and
    * otherwise returns a **randomly chosen distractor** (a different one per
      member, so wrong answers don't concentrate on one value).

  Determinism comes from seeding `:rand` per `(task id, member, seed)`, so a run
  is fully reproducible; independence comes from the member index feeding the
  seed.
  """

  alias Virtuoso.Eval.Task

  @doc """
  The answer member `member` gives for `task`.

  Options: `:error_rate` (0.0–1.0, default 0.0), `:seed` (integer, default 0).
  """
  @spec respond(Task.t(), pos_integer(), keyword()) :: String.t()
  def respond(%Task{} = task, member, opts \\ []) do
    error_rate = Keyword.get(opts, :error_rate, 0.0)
    seed = Keyword.get(opts, :seed, 0)

    state = seed_state(task.id, member, seed)
    {roll, state} = :rand.uniform_s(state)

    if roll >= error_rate do
      task.answer
    else
      pick_distractor(task.distractors, state)
    end
  end

  @doc """
  An `Ensemble.run/3`-compatible `:llm` function bound to this task.

  The runner sets `:member` on each member's request; this reads it to vary the
  response per member. Returns `{:ok, completion}` whose `text` is the answer.
  """
  @spec llm_fun(Task.t(), keyword()) :: (map(), keyword() -> {:ok, map()})
  def llm_fun(%Task{} = task, opts) do
    fn request, _call_opts ->
      member = Map.get(request, :member, 1)
      text = respond(task, member, opts)

      {:ok,
       %{
         text: text,
         model: request[:model] || "noisy",
         stop_reason: :end_turn,
         usage: %{input_tokens: 1, output_tokens: 1},
         raw: %{}
       }}
    end
  end

  # A per-(task, member, seed) rand state so runs are reproducible and members
  # err independently of one another.
  defp seed_state(task_id, member, seed) do
    a = :erlang.phash2({task_id, seed}, 1_000_000_000)
    :rand.seed_s(:exsss, {a, member * 2_654_435_761 + 1, seed + 1})
  end

  defp pick_distractor(distractors, state) do
    {index, _state} = :rand.uniform_s(length(distractors), state)
    Enum.at(distractors, index - 1)
  end
end
