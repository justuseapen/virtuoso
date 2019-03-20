defmodule Virtuoso.Bot.MapTest do
  use ExUnit.Case

  alias Virtuoso.Bot.Map

  test "list bots" do
    assert [BotMock] == Map.bots()
  end
end
