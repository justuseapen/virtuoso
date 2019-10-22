defmodule Virtuoso.Message do
  @moduledoc """
  Handles message events from Facebook Messenger
  """

  alias Virtuoso.Bot
  alias Virtuoso.Conversation
  alias Virtuoso.Translation

  def received_message(messaging) do
    sender_id = messaging["sender"]["id"]
    recipient_id = messaging["recipient"]["id"]

    messaging
    |> Translation.translate_entry()
    |> Conversation.received_message()
    |> build_response(sender_id)
  end

  def build_response(%{text: text, impression: impression} = params, sender_id) do
    build_response(text, sender_id)
    |> Map.merge(%{"impression" => impression |> Map.from_struct()})
  end

  def build_response(%{text: text} = params, sender_id) do
    build_response(text, sender_id)
  end

  def build_response(text, sender_id) do
    %{
      "messaging_type" => "RESPONSE",
      "recipient" => %{"id" => sender_id},
      "message" => %{
        "text" => text
      }
    }
  end
end
