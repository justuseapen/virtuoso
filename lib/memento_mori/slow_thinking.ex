defmodule MementoMori.SlowThinking do
  @moduledoc """
  If FastThinking failed to deduce entities and intents then SlowThinking may use a Virtuoso NLP client to determine which routine the bot should execute.
  """

  @nlp Wit.Client

  def run(impression) do
    impression
    |> maybe_get_entities
    |> maybe_get_intents
  end

  # You're trying to do too much at once
  # In the NLP class do the following
  #   Get response
  #   Atomize the hash
  #   Separate the intents from other entities
  #   Return the hash %{ intents: [], entities: [] }

  def maybe_get_entities(%{intent: _intent} = impression), do: impression
  def maybe_get_entities(%{message: message} = impression) do
    with {:ok, response} <- @nlp.get(message) do
      response
      |> gets_entities
      |> (&Map.merge(impression, %{entities: &1})).()
    end
  end

  defp gets_entities(%{body: wit_response}) do
    wit_response
    |> Poison.decode!()
    |> Map.fetch("entities")
    |> elem(1)
  end

  def maybe_get_intents(impression) do
    impression
    |> get_most_likely_intent()
    |> Map.merge(impression)
  end

  defp get_most_likely_intent(impression) do
    impression
  end
end
