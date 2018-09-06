defmodule Virtuoso.FbMessenger do
  @moduledoc"""
  Translates fb message events into Virtuoso-friendly internal representations (Impressions)
  """

  alias Virtuoso.FbMessenger.Message
  @network Application.get_env(:virtuoso, :fb_messenger_network) || Virtuoso.FbMessenger.Network


  @doc """
  Entry point for regular facebook messages (free text)
  """
  def process_messages([%{"messaging" => messaging}|_] = entries) do
    sender_id = hd(messaging)["sender"]["id"]

    start_typing_indicator(sender_id)

    entries
    |> Enum.each(&Message.received_message/1)

    stop_typing_indicator(sender_id)
  end

  @doc """
  Sends a message to Facebook to signal typing.
  """
  def start_typing_indicator(sender_id) do
    %{
      "messaging_type" => "RESPONSE",
      "recipient" => %{"id" => sender_id},
      "sender_action" => "typing_on"
    }
    |> @network.send_messenger_response()

    sender_id
  end

  @doc """
  Sends a message to Facebook to end typing signal.
  """
  def stop_typing_indicator(sender_id) do
    %{
      "messaging_type" => "RESPONSE",
      "recipient" => %{"id" => sender_id},
      "sender_action" => "typing_off"
    }
    |> @network.send_messenger_response()
  end
end
