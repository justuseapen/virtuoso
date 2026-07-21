defmodule VirtuosoDashboard.Demo do
  @moduledoc """
  Fires a real `Virtuoso.Ensemble.run/3` with the framework's own
  independently-noisy eval members — offline, no API key — so the dashboard has
  live traffic to show. Roughly a third of runs will show dissent or fall back,
  which is the interesting part.
  """

  alias Virtuoso.Ensemble
  alias Virtuoso.Ensemble.Strategy.Majority
  alias Virtuoso.Eval.NoisyMember

  @intents ["book", "cancel", "change", "refund", "status"]

  def run_once do
    intent = Enum.random(@intents)

    task = %Virtuoso.Eval.Task{
      id: "demo-#{System.unique_integer([:positive])}",
      prompt: "user wants to #{intent}",
      answer: intent,
      distractors: @intents -- [intent]
    }

    llm = NoisyMember.llm_fun(task, error_rate: 0.35, seed: :erlang.unique_integer([:positive]))
    members = for i <- 1..5, do: %{model: "noisy-demo", member: i}

    Ensemble.run(
      %{messages: [%{role: :user, content: task.prompt}]},
      members: members,
      strategy: Majority,
      extract: fn %{text: text} -> {:ok, text} end,
      llm: llm
    )
  end
end
