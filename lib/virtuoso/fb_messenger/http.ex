defmodule Virtuoso.FacebookGraphApi.Http do

  @behaviour Virtuoso.FacebookGraphApi

  alias Virtuoso.Conversation

  @headers [{"Content-Type", "application/json"}]
  @page_access_token Application.get_env(:virtuoso, :page_access_token)

  @impl Virtuoso.FacebookGraphApi
  def send_messenger_response(response) do
    url = "https://graph.facebook.com/v2.6/me/messages?access_token=#{@page_access_token}"

    case HTTPoison.post(url, Poison.encode!(response), @headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Conversation.sent_message(response["recipient"]["id"], response)
        :ok

      error ->
        error
    end
  end

  @impl Virtuoso.FacebookGraphApi
  def send_messenger_response(response, token) do
    url = "https://graph.facebook.com/v2.6/me/messages?access_token=#{token}"

    case HTTPoison.post(url, Poison.encode!(response), @headers) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Conversation.sent_message(response["recipient"]["id"], response)
        :ok

      error ->
        error
    end
  end

end
