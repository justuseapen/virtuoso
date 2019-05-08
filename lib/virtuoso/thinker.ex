defmodule Virtuoso.Thinker do
  @moduledoc """
  Use a NLP API to determine which THINKER should be executed.
  """

  @doc """
  Returns module Thinker Client used.
  """
  def module_thinker_client(nlp) do
    Module.concat(["Virtuoso", "Thinker", thinker(nlp), "Client"])
  end

  @doc """
  Returns module Thinker Slowthink used.
  """
  def module_thinker_slow_thinking(nlp) do
    Module.concat(["Virtuoso", "Thinker", thinker(nlp), "SlowThinking"])
  end

  @doc """
  Returns the Thinker used(:wit or :watson).
  """
  defp thinker(nlp) do
    nlp
    |> Atom.to_string
    |> Macro.camelize
  end
end
