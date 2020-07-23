defmodule MementoMori.SlowThinking do
  @moduledoc """
  If FastThinking failed to deduce entities and intents then SlowThinking may use a Virtuoso NLP client to determine which routine the bot should execute.
  """

  @default_nlp Application.get_env(:virtuoso, :default_nlp)

  def run(impression) when is_nil(@default_nlp) do
    impression
  end

  def run(%{intent: intent} = impression) when not is_nil(intent) do
    impression
  end

  def run(impression) do
    impression
    |> module_thinking().run
  end

  def module_thinking do
    Module.concat([@default_nlp, "Client"])
  end

  defp nlp do
    @default_nlp
    |> Atom.to_string()
    |> Macro.camelize()
  end
end
