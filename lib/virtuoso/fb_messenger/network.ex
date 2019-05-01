defmodule Virtuoso.FbMessenger.Network do
  @moduledoc """
  Handles network ops for fbmessenger medium
  """
  @facebook_graph_api Application.get_env(:virtuoso, :facebook_graph_api) || Virtuoso.FacebookGraphApi.Http

  def send_messenger_response([]), do: []

  def send_messenger_response([h | t]) do
    [send_messenger_response(h) | send_messenger_response(t)]
  end

  def send_messenger_response(response) do
    @facebook_graph_api.send_messenger_response(response)
  end

  def send_messenger_response(response, token) do
    @facebook_graph_api.send_messenger_response(response, token)
  end
end
