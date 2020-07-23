defmodule MementoMori.FastThinking do
  @moduledoc """
  FastThinking checks for intents and entities expressly implied by the impression structure or contents.
  This allows us to bypass SlowThinking when it is performant to do so.
  """

  @doc """
  Add new function definitions, pattern matching against the impression in order to catch common user intents.

  def run(%{message: "Hello Bot"} = impression) do
    impression
    |> Map.merge(%{intent: "hello_world"})
  end
  """

  def run(%{message: "Hello"} = impression) do
    impression
    |> Map.merge(%{intent: "Greeting"})
  end

  def run(impression), do: impression
end
