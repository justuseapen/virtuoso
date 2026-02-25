defmodule Virtuoso.Agent.Conversation do
  @moduledoc """
  Builds LLM message arrays from Virtuoso conversation state and impressions.

  Converts the existing `Virtuoso.Conversation.State` (which stores a list of
  sent/received messages) into the `[%{role, content}]` format expected by
  LLM providers.
  """

  alias Virtuoso.Impression

  @doc """
  Build a list of messages suitable for an LLM API call.

  Prepends the system prompt, converts conversation history to alternating
  user/assistant messages, and appends the current impression as the latest
  user message.
  """
  def build_messages(system_prompt, conversation_state, %Impression{} = impression) do
    history = build_history(conversation_state)
    current = %{role: "user", content: impression.message || ""}

    [%{role: "system", content: system_prompt}] ++ history ++ [current]
  end

  defp build_history(conversation_state) do
    messages =
      case conversation_state do
        %{messages: msgs} when is_list(msgs) -> Enum.reverse(msgs)
        _ -> []
      end

    Enum.map(messages, fn
      %Impression{message: text} ->
        %{role: "user", content: text || ""}

      %{text: text} ->
        %{role: "assistant", content: text || ""}

      text when is_binary(text) ->
        %{role: "assistant", content: text}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end
