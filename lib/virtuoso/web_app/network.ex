defmodule Virtuoso.WebApp.Network do
  @moduledoc """
  Handles network ops for web applications medium
  """

  alias Virtuoso.Conversation

  def send_messenger_response([]), do: []

  def send_messenger_response([h | t]) do
    [send_messenger_response(h) | send_messenger_response(t)]
  end

  def send_messenger_response(response) do
    Conversation.sent_message(response["recipient"]["id"], response)
    response
  end
end
