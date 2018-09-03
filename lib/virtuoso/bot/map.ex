defmodule Virtuoso.Bot.Map do
  @moduledoc """
  Lists bots
  (Needs to move to config)
  """

  def bots do
    Application.get_env(:virtuoso, :bots)
  end
end
