defmodule Virtuoso.Bot do
  @moduledoc"""
  External Interface for Bot context
  """

  alias Virtuoso.Bot.Map

  def get(recipient_id) do
    Map.bots
    |> Enum.find(fn(bot) -> bot.recipient_id == recipient_id end)
  end

  def handles_message(bot, impression, conversation_state) do
    impression
    |> bot.respond_to(conversation_state)
  end
end
