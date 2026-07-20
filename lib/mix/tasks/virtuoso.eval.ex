defmodule Mix.Tasks.Virtuoso.Eval do
  @shortdoc "Run the ensemble eval harness: single-call vs N-way consensus accuracy"
  @moduledoc """
  Runs the offline eval harness and prints an accuracy table proving N-way
  consensus beats a single call on categorical (routing/extraction) tasks.

  The "models" are deterministic noisy members (`Virtuoso.Eval.NoisyMember`) that
  err independently, so a majority of N corrects the single call's mistakes —
  the mechanism the flagship rests on. No network, fully reproducible.

      mix virtuoso.eval
      mix virtuoso.eval --error-rate 0.35 --seeds 20

  Options:
    * `--error-rate` — per-member error rate (default sweeps 0.2/0.35/0.5)
    * `--n` — ensemble sizes (default sweeps 3/5/9)
    * `--seeds` — number of seeds to average over (default 12)
  """
  use Mix.Task

  alias Virtuoso.Eval.{Runner, Task}

  # The harness runs the real Ensemble, which needs the app's Task.Supervisor.
  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [error_rate: :float, n: :integer, seeds: :integer]
      )

    seeds = Keyword.get(opts, :seeds, 12)
    error_rates = if opts[:error_rate], do: [opts[:error_rate]], else: [0.2, 0.35, 0.5]
    ns = if opts[:n], do: [opts[:n]], else: [3, 5, 9]

    Mix.shell().info("Ensemble eval — single-call vs majority-of-N (avg over #{seeds} seeds)\n")
    Mix.shell().info("err  | n | single | ensemble |  gain")
    Mix.shell().info("-----|---|--------|----------|-------")

    for error_rate <- error_rates, n <- ns do
      {single, ensemble} = averaged(tasks(), n, error_rate, seeds)
      gain = ensemble - single

      row =
        :io_lib.format("~.2f | ~w | ~5.1f% | ~6.1f% | +~.1f pts", [
          error_rate,
          n,
          single * 100,
          ensemble * 100,
          gain * 100
        ])

      Mix.shell().info(to_string(row))
    end
  end

  defp averaged(tasks, n, error_rate, seeds) do
    {s, e} =
      Enum.reduce(1..seeds, {0.0, 0.0}, fn seed, {sa, ea} ->
        r = Runner.run(tasks, n: n, error_rate: error_rate, seed: seed)
        {sa + r.single_accuracy, ea + r.ensemble_accuracy}
      end)

    {s / seeds, e / seeds}
  end

  # A default categorical routing task set.
  defp tasks do
    intents = ["book", "cancel", "change", "refund", "status", "upgrade"]

    Enum.map(Enum.with_index(intents), fn {intent, i} ->
      %Task{
        id: "task-#{i}",
        prompt: "user wants to #{intent}",
        answer: intent,
        distractors: intents -- [intent]
      }
    end)
  end
end
