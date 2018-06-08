defmodule Medium.FbMessenger.Message do
  @moduledoc """
  Handles message events from Facebook Messenger
  """

  alias Virtuoso.Conversation
  alias Virtuoso.Executive
  alias Medium.FbMessenger.Translation
  alias Medium.FbMessenger.Network

  def received_message(%{"messaging" => [entry | _]}) do
    sender_id = entry["sender"]["id"]

    entry
    |> Translation.translate_entry()
    |> Conversation.received_message()
    |> Executive.handles_message()
    |> build_response(sender_id)
    |> Network.send_messenger_response()
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
