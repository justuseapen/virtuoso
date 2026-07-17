defmodule Virtuoso.Channel.WebChat do
  @moduledoc """
  Web-chat channel adapter — the first-class channel for the rebuild.

  Identity is **session-based**: the session id is the conversation id, so a
  browser session maps to one conversation process. This adapter is Phoenix-free
  — it only translates between the web wire format and `Virtuoso.Impression`.
  The transport that carries these payloads (a Phoenix Channels socket or
  LiveView) lives in the host application and calls `translate_in/1` on receipt
  and `send_out/2` to render a reply.

  Web chat authenticates via the session, not webhook signatures, so
  `verify_webhook/2` is a no-op that returns `:ok`.
  """

  @behaviour Virtuoso.Channel

  alias Virtuoso.Impression

  @impl true
  def translate_in(
        %{
          "session_id" => session_id,
          "user_id" => user_id,
          "message_id" => message_id,
          "text" => text
        } = raw
      ) do
    imp =
      Impression.new(
        channel: :web_chat,
        conversation_id: session_id,
        sender_id: user_id,
        message_id: message_id,
        text: text,
        metadata: Map.get(raw, "metadata", %{})
      )

    {:ok, imp}
  end

  def translate_in(_raw), do: {:error, :invalid_payload}

  @impl true
  def send_out(%Impression{conversation_id: session_id}, reply_text) do
    {:ok, %{session_id: session_id, text: reply_text}}
  end

  @impl true
  def verify_webhook(_raw_body, _opts), do: :ok
end
