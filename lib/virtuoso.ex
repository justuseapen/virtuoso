defmodule Virtuoso do
  @moduledoc """
  Virtuoso is a BEAM-native AI-agent orchestration framework.

  It implements two architectural ideas as first-class OTP concerns:

    * **Actor-based parallel consensus** (`Virtuoso.Ensemble`) — many lightweight
      processes run LLM calls concurrently and aggregate their structured outputs
      by consensus, judging, or quorum, instead of a single serial call chain.

    * **Distributed compute fabric** (`Virtuoso.Fabric`) — a multi-node cluster
      with automatic failure recovery and horizontal scaling of conversations.

  The framework keeps the cognitive shape of a classic bot pipeline — a
  deterministic fast path (`Virtuoso.Thinking.Fast`) ahead of an LLM reasoning
  step (`Virtuoso.Thinking.Slow`) — but swaps the pre-LLM NLP guts for LLM
  ensembles behind the `Virtuoso.LLM` behaviour.

  Messages enter as channel-neutral `Virtuoso.Impression` envelopes.
  """
end
