defmodule Virtuoso.Executive do
  @moduledoc """
  Receives impressions and delegates to relevant bot and subroutine
  """

  alias Virtuoso.Ego
  alias Virtuoso.Bot

  def handles_message({%{recipient_id: recipient_id} = impression, conversation_state}) do

    # eventually delegate these functions to the EGO
    # If unknown, ask SUPEREGO for help

    recipient_id
    |> identify()
    |> get_subroutine(impression, conversation_state)
  end

  def identify(receiver_id), do: Virtuoso.Bot.get(receiver_id)

  def get_subroutine(bot, impression, conversation_state) do
    bot
    |> Bot.handles_message(impression, conversation_state)
  end
end
