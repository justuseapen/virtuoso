defmodule Virtuoso.Bot.Map do
  @moduledoc """
  Lists bots from bot.lock
  """
  alias Virtuoso.Utilities.Util

  def bots do
    Util.get_current_state!() |> Poison.decode!() |> Map.keys()
  end
end
