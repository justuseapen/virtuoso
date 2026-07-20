defmodule Virtuoso.Thinking do
  @moduledoc """
  The thinking pipeline — FastThinking → SlowThinking — as a conversation
  responder.

  `responder/1` builds the `(impression, history -> {:reply, text} | :noreply)`
  function that `Virtuoso.Conversation` plugs in as its `:responder`. This is the
  seam left open in Phase 1, now filled: it connects an inbound message to the
  cognitive pipeline and back to a reply.

  For each message:

    1. **FastThinking** (`Virtuoso.Thinking.Fast`) offers a deterministic,
       zero-token answer. If a matcher hits, that decision is the reply — no
       tokens spent.
    2. On `:no_match`, **SlowThinking** (`Virtuoso.Thinking.Slow`) runs: the
       *routing* decision goes through `Virtuoso.Ensemble` (structured
       consensus over routine names), then the resolved routine generates the
       reply (single-model, not voted).

  ## Options (passed straight to the pipeline)
    * `:fast` — list of `Virtuoso.Thinking.Fast` matcher modules (default `[]`).
    * `:routines` — `%{name => module}` registry for SlowThinking (default `%{}`).
    * `:ensemble`, `:llm`, `:fallback`, `:system` — forwarded to `Slow.respond/3`.

  The `history` the responder receives is used as SlowThinking context (available
  to routines and, later, to the LLM prompt).
  """

  alias Virtuoso.Impression
  alias Virtuoso.Thinking.{Fast, Slow}

  @type responder :: (Impression.t(), list() -> {:reply, String.t()} | :noreply)

  @doc "Build the Fast→Slow responder for `Virtuoso.Conversation`."
  @spec responder(keyword()) :: responder()
  def responder(opts) do
    fast = Keyword.get(opts, :fast, [])
    slow_opts = Keyword.put_new(opts, :routines, %{})

    fn %Impression{} = imp, history ->
      context = %{history: history}

      case Fast.run(fast, imp, context) do
        {:match, decision} -> decision
        :no_match -> Slow.respond(imp, context, slow_opts)
      end
    end
  end
end
