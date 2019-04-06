defmodule FbMessenger.Bot.MapTest do
  use ExUnit.Case

  alias FbMessenger.Bot.Map

  test "list bots" do
    assert [BotMock] == Map.bots()
  end
end
