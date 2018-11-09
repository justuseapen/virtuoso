defmodule Virtuoso.NLPMock do
  @moduledoc """
  """
  def get(message) do
    body =
      %{
        message: message,
        entities: %{
          intent: 'test',
          confidence: 1.0
        }
      }
      |> Poison.encode!()

    {:ok, %{body: body}}
  end
end
