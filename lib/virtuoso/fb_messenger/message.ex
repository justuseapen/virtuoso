defmodule Virtuoso.FbMessenger.Message do
  @moduledoc """
  Handles message events from Facebook Messenger
  """

  alias Virtuoso.Bot
  alias Virtuoso.Conversation
  alias Virtuoso.Executive
  alias Virtuoso.FbMessenger.Translation
  alias Virtuoso.FbMessenger.Network

  def received_message(%{"messaging" => [entry | _]}) do
    sender_id = entry["sender"]["id"]
    recipient_id = entry["recipient"]["id"]
    token = Bot.get_token_by_recipient_id(recipient_id, :fb)

    entry
    |> Translation.translate_entry()
    |> Conversation.received_message()
    |> Executive.handles_message()
    |> build_response(sender_id)
    |> Network.send_messenger_response(token)
  end

  def build_response(text, sender_id) do
    %{
      "messaging_type" => "RESPONSE",
      "recipient" => %{"id" => sender_id},
      "message" => %{
        "text" => text,
      }
    }
  end
end
