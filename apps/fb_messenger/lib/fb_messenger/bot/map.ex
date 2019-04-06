defmodule FbMessenger.Bot.Map do
  @moduledoc """
  Lists bots
  """

  def bots do
    Application.get_env(:fb_messenger, :bots)
  end
end
