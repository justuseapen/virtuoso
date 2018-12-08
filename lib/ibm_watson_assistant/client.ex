defmodule IbmWatsonAssistant.Client do
  @moduledoc """
    IBM Watson Assistant AI integration for intent handling and NLP
  """
  alias Virtuoso.Conversation

  @api_version Application.get_env(:virtuoso, :ibm_watson_assistant_version)
  @assistance_id Application.get_env(:virtuoso, :ibm_watson_assistant_id)
  @token Application.get_env(:virtuoso, :ibm_watson_assistant_token)
  @endpoint_url "https://gateway.watsonplatform.net/assistant/api/v2/assistants/#{@assistance_id}"

  @options [
    params: %{
      "version" => @api_version
    }
  ]

  @headers [
    "Authorization": "Basic #{@token}",
    "Content-Type": "application/json"
  ]

  @doc """
  Requests a session ID from Watson Assistant AI NLP analysis. Returns a response number.
  """
  def get_session(sender_id) do
    url =
      @endpoint_url
      |> _append_to_url("sessions")
      |> create_url(@options |> hd |> elem(1))

    {:ok, response} = HTTPoison.post(url, [], @headers)
  end

  @doc """
  Requests a Watson Assistant AI NLP analysis. Returns a response object.
  """
  def think_and_answer(session_id, text) do
    url =
      @endpoint_url
      |> _append_to_url("sessions/#{session_id}/message")
      |> create_url(@options |> hd |> elem(1))

    input = %{"text": text}
    body = Poison.encode!(%{"input": input})

    {:ok, response} =
      HTTPoison.post(url, body, @headers)
      |> case do
        {:ok, %{body: raw, status_code: code}} -> {:ok, raw}
        {:error, %{reason: reason}} -> {:error, reason}
      end
      |>  (fn {code, body} ->
        body
        |> Poison.decode(keys: :atoms)
        |> case do
             {:ok, parsed} -> {:ok, parsed}
             _ -> {:error, body}
           end
         end).()
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

  defp _append_to_url(url, _method), do: "#{url}/#{_method}"
  defp _append_to_url(url, _key, ""), do: url
  defp _append_to_url(url, key, param), do: "#{url}?#{key}=#{param}"

end
