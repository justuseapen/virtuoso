defmodule Wit.Agent do
  @moduledoc """
    WIT AI integration for intent handling and NLP
  """

  @token Application.get_env(:virtuoso, :wit_server_access_token)
  @message_url "https://api.wit.ai/message?"
  @api_version "20171201"

  @doc """
  Requests a Wit AI NLP analysis. Returns a response object.
  """
  def get(text) do
    options = [
      params: %{
        "q" => URI.encode(text),
        "v" => @api_version
      }
    ]

    headers = [Authorization: "Bearer #{@token}", Accept: "Application/json; Charset=utf-8"]

    url =
      @message_url
      |> create_url(options |> hd |> elem(1))

    response =
      url
      |> HTTPoison.get!(headers)

    {:ok, response}
  end

  @doc """
  Returns :undefined because wit don't controll session.
  """
  def create_session do
    {:undefined}
  end

  # Creates a request URL according to Wit specs
  defp create_url(endpoint, %{} = params) do
    params
    |> Map.keys()
    |> Enum.reverse()
    |> Enum.reduce(endpoint, fn key, url ->
      _append_to_url(url, key, Map.get(params, key))
    end)
  end

  defp _append_to_url(url, _key, ""), do: url
  defp _append_to_url(url, key, param), do: "#{url}&#{key}=#{param}"
end
