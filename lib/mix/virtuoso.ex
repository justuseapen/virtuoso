defmodule Mix.Virtuoso do
  @moduledoc false
  # Shared helpers for the virtuoso.gen.* tasks.

  @doc """
  Validate a CLI argument as an Elixir module namespace (`Demo`, `MyApp.Bots`).

  Returns `{module_string, underscored_path}`; raises `Mix.Error` otherwise.
  """
  @spec module_arg!(String.t(), String.t()) :: {String.t(), String.t()}
  def module_arg!(arg, what) do
    if arg =~ ~r/^[A-Z]\w*(\.[A-Z]\w*)*$/ do
      {arg, Macro.underscore(arg)}
    else
      Mix.raise(
        "Expected the #{what} to be a valid module name (e.g. Demo or MyApp.Demo), got: " <>
          inspect(arg)
      )
    end
  end
end
