defmodule Wit.Client do
  @moduledoc """
  If FastThinking failed to deduce entities and intents then SlowThinking may use a Virtuoso NLP client to determine which routine the bot should execute.
  """

  def run(impression) do
    impression
    |> maybe_get_entities
    |> maybe_get_intents
  end

  def maybe_get_entities(%{intent: _intent} = impression), do: impression
  # message is nil when the incoming message is an image
  def maybe_get_entities(%{message: nil} = impression), do: impression

  def maybe_get_entities(%{message: message} = impression) do
    with {:ok, response} <- Wit.Agent.get(message) do
      response
      |> gets_entities
      |> (&Map.merge(impression, %{entities: &1})).()
    end
  end

  defp gets_entities(%{body: nlp_response}) do
    nlp_response
    |> Poison.decode!()
    |> Map.fetch("entities")
    |> elem(1)
  end

  def maybe_get_intents(impression) do
    impression
    |> get_most_likely_intent()
    |> Map.merge(impression)
  end

  defp get_most_likely_intent(
         %{entities: %{"intent" => [%{"value" => intent} | _t]}} = impression
       ) do
    impression
    |> Map.merge(%{intent: intent})
  end

  defp get_most_likely_intent(%{entities: %{}} = impression) do
    impression
  end

  defp get_most_likely_intent(impression) do
    impression
  end
end
