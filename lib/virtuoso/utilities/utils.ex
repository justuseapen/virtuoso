defmodule Virtuoso.Utilities.Util do
  @moduledoc """
      Contains all utility, non-contextual functions
  """

  @doc """
      Helper function to atomize map keys
  """
  def atomic_map(string_key_map) do
    for {key, val} <- string_key_map, into: %{}, do: {String.to_atom(key), val}
  end

  def get_current_state() do
    case File.read("bot.lock") do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:ok, %{MementoMori: ["active", "default"]} |> Poison.encode!()}
    end
  end

  def get_current_state!() do
    {:ok, content} = get_current_state()
    content
  end

  @doc """
    Convert input string value of a bot into a Module atom
  """
  def get_bot_module(name) do
    ("Elixir." <> name) |> String.to_atom()
  end

  @doc """
    Format Bot map into an array containing map of botname and props
  """
  def format_bot_list(bots) do
    bots |> Map.keys() |> Enum.map(fn bot -> %{botname: bot, props: Map.get(bots, bot)} end)
  end
end
