defmodule Virtuoso.Admin.Dashboard do
  alias Virtuoso.Utilities.Util

  @doc """
      List out all default and user generated bots
      iex>list_bots()
      %{
          BotName: ["active", "user_created"],
          MomentoMori: ["active", "default"]
      }
  """
  def list_bots() do
    bots = Util.get_current_state!() |> Poison.decode!() |> Util.atomic_map()
    Util.format_bot_list(bots)
  end

  @doc """
    Send message params to virtuoso module
  """
  def send_message(params) do
    params
    |> Virtuoso.handle()
  end
end
