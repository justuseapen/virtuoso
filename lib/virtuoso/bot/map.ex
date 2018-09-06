defmodule Virtuoso.Bot.Map do
  @moduledoc """
  Lists bots
  """

  def bots do
    Application.get_env(:virtuoso, :bots)
  end
end
