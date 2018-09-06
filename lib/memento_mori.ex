defmodule MementoMori do
  @moduledoc """
  Remember Death
  """
  alias MementoMori.FastThinking
  alias MementoMori.SlowThinking
  alias MementoMori.Routine

  @recipient_ids [
    Application.get_env(:memento_mori, :fb_page_recipient_id)
  ]

  @tokens %{
    fb_page_access_token: Application.get_env(:memento_mori, :fb_page_access_token)
  }

  @doc """
  Getter for receiver_id
  """
  def recipient_ids(), do: @recipient_ids

  @doc """
  Gets token by client
  """
  def token(:fb), do: @tokens[:fb_page_access_token]

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
