defmodule Virtuoso.WebApp.Message do
  @moduledoc """
  Handles message events from Web Applications
  """

  alias Virtuoso.Bot
  alias Virtuoso.Conversation
  alias Virtuoso.WebApp.Translation
  alias Virtuoso.WebApp.Network

  def received_message(entry) do
    entry
    |> Translation.translate_entry
    |> Conversation.received_message
    |> Conversation.save_session
#    |> build_response(uid)
  end

  def build([], sender_id) do
     build_response("", sender_id)
   end
  def build([h | t], sender_id) do
    [build_response(h[:text], sender_id) | build(t, sender_id)]
  end

  def build_response(%{responses: responses} = impression, sender_id) do
    responses
    |> build(sender_id)
  end
  def build_response(text, sender_id) do
    %{
      "messaging_type" => "RESPONSE",
      "recipient" => %{"id" => sender_id},
      "message" => %{
        "text" => text
      }
    }
    |> Network.send_messenger_response
  end
end
