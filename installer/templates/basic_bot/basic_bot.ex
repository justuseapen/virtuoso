defmodule MementoMori do
  @moduledoc """
  Remember Death
  """
  alias MementoMori.FastThinking
  alias MementoMori.SlowThinking
  alias MementoMori.Routine

  @recipient_id "217557272146428"

  @doc """
  Getter for receiver_id
  """
  def recipient_id(), do: @recipient_id

  @doc """
  Main pipeline for the bot.
  """
  def respond_to(impression, conversation_state) do
    impression
    |> FastThinking.run()
    |> SlowThinking.run()
    |> Routine.runner(conversation_state)
  end
end
