defmodule Virtuoso.Thinker do
  @moduledoc """
  Use a NLP API to determine which THINKER should be executed.
  """

  @default_nlp Application.get_env(:virtuoso, :default_nlp) || nil

  @doc """
  Returns module Thinker used.
  """
  def module_thinker_client do
    Module.concat([thinker(), "Client"])
  end

  @doc """
  Returns the Thinker used(:wit or :watson).
  """
  defp thinker do
    @default_nlp
    |> Atom.to_string()
    |> Macro.camelize()
  end
end
