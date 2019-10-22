defmodule MementoMori.Routine do
  @moduledoc """
  Interface for all of MM's routines.
  """

  @module_name_expanded "Elixir.MementoMori.Routine."
  @default_routine MementoMori.Routine.Default

  @doc """
  Initiates a routine given a corresponding intent string.
  Intent string gets converted into corresponding routine module name
  and calls run function in routine module dynamically.
  """
  def runner(%{intent: intent} = impression, _conversation_state) do
    intent
    |> Macro.camelize()
    |> String.replace_prefix("", @module_name_expanded)
    |> String.to_existing_atom()
    |> apply(:run, [impression])
  end

  def runner(impression, _conversation_state) do
    @default_routine.run(impression)
  end
end
