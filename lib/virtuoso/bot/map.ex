defmodule Virtuoso.Bot.Map do
  @moduledoc """
  Maps bots by receiver ID
  """

  def bots do
    with {:ok, modules} <- :application.get_key(:virtuoso, :modules) do
      modules
      |> _only_bots
    end
  end

  #
  # Filters non Virtuoso.Bot modules
  # Filters self
  #
  #
  defp _only_bots(modules) do
    modules
    |> Enum.filter(& &1 |> Module.split |> Enum.take(2) == ~w|Virtuoso Bot|)
    |> Enum.filter(& &1 != __MODULE__)
    |> Enum.filter(& &1 |> Module.split |> length > 2)
  end
end
