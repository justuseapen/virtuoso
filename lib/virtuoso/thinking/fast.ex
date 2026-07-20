defmodule Virtuoso.Thinking.Fast do
  @moduledoc """
  FastThinking — the deterministic, zero-token fast path.

  Before spending any LLM tokens, a message is offered to a bot's fast-thinkers:
  cheap pattern matches for the cases a bot can answer without reasoning
  (greetings, explicit commands, structured payloads like button postbacks). A
  matcher returns a decision directly; only on `:no_match` does the message fall
  through to `Virtuoso.Thinking.Slow` (the LLM step).

  This preserves the legacy framework's cognitive shape — FastThinking →
  SlowThinking — while the guts underneath change from NLP to LLM ensembles.

  A fast-thinker implements `match/2`:

      defmodule MyBot.Fast.Greeting do
        @behaviour Virtuoso.Thinking.Fast
        @impl true
        def match(%Impression{text: text}, _ctx) do
          if greeting?(text), do: {:match, {:reply, "Hi!"}}, else: :no_match
        end
      end
  """

  alias Virtuoso.Impression

  @type decision :: {:reply, String.t()} | :noreply
  @type context :: map()

  @doc "Match an impression, or `:no_match` to fall through to the LLM step."
  @callback match(Impression.t(), context()) :: {:match, decision()} | :no_match

  @doc """
  Offer the impression to each matcher in order; return the first `{:match, _}`,
  or `:no_match` if none match.
  """
  @spec run([module()], Impression.t(), context()) :: {:match, decision()} | :no_match
  def run(matchers, %Impression{} = imp, context) do
    Enum.reduce_while(matchers, :no_match, fn matcher, _acc ->
      case matcher.match(imp, context) do
        {:match, _decision} = hit -> {:halt, hit}
        :no_match -> {:cont, :no_match}
      end
    end)
  end
end
