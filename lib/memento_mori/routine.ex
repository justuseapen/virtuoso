defmodule MementoMori.Routine do
  @moduledoc """
  Interface for all of MM's routines.
  """

  @module_name_expanded  "Elixir.MementoMori.Routine."
  @default_routine MementoMori.Routine.Greeting

  @doc """
  Initiates a routine given a corresponding intent string.
  Intent string gets converted into corresponding routine module name
  and calls run function in routine module dynamically.
  """
  def runner(%{intent: intent} = impression, conversation_state) do
    intent
    |> String.replace(" ", "")
    |> Macro.camelize
    |> String.replace_prefix("", @module_name_expanded)
    |> String.to_existing_atom
    |> apply(:run, impression)
  end
  def runner(impression, conversation_state) do
    @default_routine.run()
  end
end
