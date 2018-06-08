defmodule Virtuoso.Bot.MementoMori do
  @moduledoc """
  Remember Death
  """

  @recipient_id "217557272146428"

  @doc """
  Getter for receiver_id
  """
  def recipient_id(), do: @recipient_id

  @doc """
  """
  def respond_to(impression, conversation_state) do
    "Yo."
  end
end
