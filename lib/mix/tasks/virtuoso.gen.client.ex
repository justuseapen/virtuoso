defmodule Mix.Tasks.Virtuoso.Gen.Client do
  @moduledoc """
  Generates a webhook
  """

  use Mix.Task
  alias Mix.Generator

  @otp_app Mix.Phoenix.otp_app() |> to_string() |> Mix.Phoenix.inflect()

  @doc """
  Given the application module will generate a webhook
  """
  def run(_args) do
    _get_bot_web_controller_directory() |> _generate_webhook()
  end

  def _generate_webhook(dir) do
    dir
    |> String.replace_suffix("", "webhook_controller.ex")
    |> Generator.create_file(webhook_controller_template())
  end

  def _get_bot_web_controller_directory() do
    File.cwd!()
    |> String.replace_suffix("", "/lib/#{@otp_app[:path]}_web/controllers/")
  end

  def webhook_controller_template() do
    web_module = "#{@otp_app[:alias]}Web"

    """
    defmodule #{web_module}.WebhookController do
      use #{web_module}, :controller

      def create(conn, params) do
        params
        |> Virtuoso.handle()

        send_resp(conn, 200, "EVENT_RECEIVED")
      end

      def verify(conn, %{"hub.mode" => mode, "hub.verify_token" => token, "hub.challenge" => challenge}) do
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
    """
  end
end
