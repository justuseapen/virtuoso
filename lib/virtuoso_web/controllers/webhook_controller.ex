defmodule VirtuosoWeb.WebhookController do
  use VirtuosoWeb, :controller

  def create(conn, params) do
    params
    |> Virtuoso.handle()

    send_resp(conn, 200, "EVENT_RECEIVED")
  end

  def verify(conn, %{
        "hub.mode" => mode,
        "hub.verify_token" => token,
        "hub.challenge" => challenge
      }) do
    with :ok <- verify_mode(mode),
         :ok <- verify_token(token),
         {:ok, challenge} <- verify_challenge(challenge) do
      send_resp(conn, 200, challenge)
    else
      {:error, error} -> send_resp(conn, 403, error)
    end
  end

  defp verify_mode("subscribe"), do: :ok
  defp verify_mode(_), do: {:error, "Must be in subscribe mode"}

  defp verify_token("asdf"), do: :ok
  defp verify_token(_), do: {:error, "Failed token verification"}

  defp verify_challenge(challenge) when is_nil(challenge), do: {:error, "Missing challenge param"}
  defp verify_challenge(challenge), do: {:ok, challenge}
end
