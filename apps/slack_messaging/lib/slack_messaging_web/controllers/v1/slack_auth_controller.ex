defmodule SlackMessagingWeb.V1.SlackAuthController do
  use SlackMessagingWeb, :controller

  require Logger

  @root_url Application.get_env(:slack_messaging, :root_url)
  @client_id Application.get_env(:slack_messaging, :client_id)
  @client_secret Application.get_env(:slack_messaging, :client_secret)

  def request(conn, %{"provider" => _provider, "code" => code, "state" => _state}) do
    can_perform_request? = slack_setup_successful?()
    slack_account_details = get_slack_account_details(conn, code, can_perform_request?)

    case slack_account_details["ok"] do
      false ->
        Logger.info(":error Slack reponded with : \n#{inspect(slack_account_details["error"])}")

        conn
        |> put_status(401)
        |> json(%{
          message: "Slack error: #{inspect(slack_account_details["error"])}"
        })

      _ ->
        Logger.info("Registered Slack user #{slack_account_details["user_id"]}")

        redirect(conn, external: @root_url)

    end
  end

  def request(conn, %{"provider" => provider}) do
    conn
    |> put_status(400)
    |> json(%{
      message: "Missing params"
    })
  end

  defp get_slack_account_details(conn, code, false) do
    conn
    |> put_status(400)
    |> json(%{message: "Missing Slack configs"})
  end

  defp get_slack_account_details(_conn, code, true) do
    Logger.info("slack redirect url: #{@root_url}")

    Slack.Web.Oauth.access(
      @client_id, @client_secret,
      @code,
      %{
        redirect_uri: @root_url
      }
    )
  end

  defp get_slack_account_details(_conn, nil, _can_perform_request?), do: "Missing code"

  defp slack_setup_successful?() do
    if @root_url && @client_id && @client_secret, do: true, else: false
  end

end
