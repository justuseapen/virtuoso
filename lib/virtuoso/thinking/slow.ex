defmodule Virtuoso.Thinking.Slow do
  @moduledoc """
  SlowThinking — the LLM reasoning step.

  When FastThinking doesn't match, the message reaches here. Per the plan's
  design decision 5, **the routing decision goes through the Ensemble** (a short,
  structured consensus over which routine handles the message) while
  **generation stays single-model** — the chosen routine produces the reply
  once, not once per member. Consensus is on the decision, not the text; N
  members never mean N replies (or N side effects).

  Flow: build member variants → `Ensemble.run/3` votes on a routine name →
  resolve the name through the `Virtuoso.Routine` registry (no `String.to_atom`)
  → the routine generates the reply. An unknown/hallucinated route or a failed
  ensemble degrades to a defined fallback reply, never a crash.

  ## Options
    * `:routines` — `%{name => module}` registry (required).
    * `:ensemble` — `[n: 3, strategy: Majority, models: [...], strategy_opts: ...]`.
    * `:llm` — the `Ensemble.run/3` `:llm` seam (default `&Virtuoso.LLM.complete/2`).
    * `:fallback` — reply text when routing can't resolve (has a sensible default).
    * `:system` — routing system prompt override.
  """

  alias Virtuoso.{Ensemble, Impression, LLM, Routine}
  alias Virtuoso.Ensemble.Strategy.Majority

  @default_fallback "I'm not sure how to help with that yet. Could you rephrase?"

  @spec respond(Impression.t(), map(), keyword()) :: {:reply, String.t()} | :noreply
  def respond(%Impression{} = imp, context, opts) do
    routines = Keyword.fetch!(opts, :routines)
    ensemble = Keyword.get(opts, :ensemble, [])
    fallback = Keyword.get(opts, :fallback, @default_fallback)

    case route(imp, routines, ensemble, opts) do
      {:ok, name} -> dispatch(routines, name, imp, context, fallback)
      :no_route -> {:reply, fallback}
    end
  end

  # Run the routing decision through the ensemble; return the committed routine
  # name (consensus or single-model fallback), or :no_route on total failure.
  defp route(imp, routines, ensemble, opts) do
    names = Map.keys(routines)
    n = Keyword.get(ensemble, :n, 3)
    strategy = Keyword.get(ensemble, :strategy, Majority)
    strategy_opts = Keyword.get(ensemble, :strategy_opts, [])
    models = Keyword.get(ensemble, :models, [])
    llm = Keyword.get(opts, :llm, &LLM.complete/2)

    run_opts = [
      members: members(n, models),
      strategy: strategy,
      strategy_opts: strategy_opts,
      extract: &extract_route/1,
      llm: llm
    ]

    case Ensemble.run(routing_request(imp, names, opts), run_opts) do
      {:consensus, name, _meta} -> {:ok, name}
      {:fallback, name, _meta} -> {:ok, name}
      {:error, :all_members_failed, _meta} -> :no_route
    end
  end

  # One member per model (cycling if fewer models than n); each tagged so the
  # test llm/real adapter can vary per member.
  defp members(n, []), do: for(i <- 1..n, do: %{member: i})

  defp members(n, models) do
    for i <- 1..n do
      model = Enum.at(models, rem(i - 1, length(models)))
      %{member: i, model: model}
    end
  end

  defp routing_request(imp, names, opts) do
    system =
      Keyword.get(opts, :system) ||
        """
        You are a router. Choose exactly one intent that best handles the user's \
        message. Valid intents: #{Enum.join(names, ", ")}. Reply with ONLY the \
        intent name, nothing else.
        """

    %{
      system: system,
      messages: [%{role: :user, content: imp.text || ""}]
    }
  end

  # Extract a clean routine name from a member's completion text.
  defp extract_route(%{text: text}) when is_binary(text) do
    {:ok, text |> String.trim() |> String.downcase()}
  end

  defp extract_route(_), do: :error

  defp dispatch(routines, name, imp, context, fallback) do
    case Routine.dispatch(routines, name, imp, context) do
      {:reply, _text} = reply -> reply
      :noreply -> :noreply
      {:error, :unknown_routine} -> {:reply, fallback}
      {:error, _other} -> {:reply, fallback}
    end
  end
end
