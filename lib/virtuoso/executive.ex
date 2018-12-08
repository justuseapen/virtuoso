defmodule Virtuoso.Executive do
  @moduledoc """
  Receives impressions and delegates to relevant bot and subroutine
  """

  alias Virtuoso.Bot

  def handles_message({%{recipient_id: recipient_id, origin: origin} = impression, conversation_state}) do
    recipient_id
    |> identify(origin)
    |> get_subroutine(impression, conversation_state)
  end

  # Matches recipient_id to corresponding bot
  defp identify(receiver_id, :messenger), do: Virtuoso.Bot.get(receiver_id)
  defp identify(receiver_id, :webapp), do: Virtuoso.Bot.get

  # Gets the relevant subroutine from the relevant bot
  defp get_subroutine(bot, impression, conversation_state) do
    bot
    |> Bot.handles_message(impression, conversation_state)
  end
end
