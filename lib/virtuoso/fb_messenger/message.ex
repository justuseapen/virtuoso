defmodule Virtuoso.FbMessenger.Message do
  @moduledoc """
  Handles message events from Facebook Messenger
  """

  alias Virtuoso.Bot
  alias Virtuoso.Conversation
  alias Virtuoso.FbMessenger.Translation
  alias Virtuoso.FbMessenger.Network

  def received_message(%{"messaging" => [entry | _]}) do
    sender_id = entry["sender"]["id"]
    recipient_id = entry["recipient"]["id"]
    token = Bot.get_token_by_recipient_id(recipient_id, :fb)

    entry
    |> Translation.translate_entry
    |> Conversation.received_message
    |> Conversation.save_session
    |> build_response(sender_id, token)
  end

  def build([], sender_id, token) do
     build_response("", sender_id, token)
   end
  def build([h | t], sender_id, token) do
    [build_response(h[:text], sender_id, token) | build(t, sender_id, token)]
  end

  def build_response(%{responses: responses} = impression, sender_id, token) do
    responses
    |> build(sender_id, token)
  end
  def build_response(text, sender_id, token) do
    %{
      "messaging_type" => "RESPONSE",
      "recipient" => %{"id" => sender_id},
      "message" => %{
        "text" => text
      }
    }
    |> Network.send_messenger_response(token)
  end
end
