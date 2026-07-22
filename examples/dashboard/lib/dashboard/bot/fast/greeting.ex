defmodule VirtuosoDashboard.Bot.Fast.Greeting do
  @moduledoc "Zero-token greeting matcher — the demo's visible fast path."

  @behaviour Virtuoso.Thinking.Fast

  alias Virtuoso.Impression

  @greetings ~w(hi hello hey howdy yo)

  @impl true
  def match(%Impression{text: text}, _context) when is_binary(text) do
    if String.downcase(String.trim(text)) in @greetings do
      {:match,
       {:reply,
        "Hello! I'm Virtuoso Chat. This greeting took the deterministic fast " <>
          "path — zero tokens. Ask me anything and watch the ensemble vote " <>
          "in the panel."}}
    else
      :no_match
    end
  end

  def match(_impression, _context), do: :no_match
end
