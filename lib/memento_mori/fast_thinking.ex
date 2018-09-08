defmodule MementoMori.FastThinking do
  @moduledoc """
  FastThinking checks for intents and entities expressly implied by the impression structure or contents.
  This allows us to bypass SlowThinking when it is performant to do so.
  """

  def run(%{message: "25"} = impression) do
    impression
    |> Map.merge(%{intent: "time_left"})
  end
  def run(impression), do: impression
end
