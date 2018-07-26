defmodule Medium.FbMessenger.Network do
  # TODO: This Module should be able to accommodate n facebook pages

  @moduledoc """
  Handles network ops for fbmessenger medium
  """

  alias Virtuoso.Conversation

  @page_access_token Application.get_env(:virtuoso, :page_access_token)
  @headers [{"Content-Type", "application/json"}]

  def send_messenger_response([]), do: []
  def send_messenger_response([h|t]) do
    [send_messenger_response(h)|send_messenger_response(t)]
  end
  def send_messenger_response(response) do
    start_time = Timex.now()
    url = "https://graph.facebook.com/v2.6/me/messages?access_token=#{@page_access_token}"

    case HTTPoison.post(url, Poison.encode!(response), @headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Conversation.sent_message(response["recipient"]["id"], response)
        :ok
      error ->
        error |> IO.inspect
    end
  end
end
