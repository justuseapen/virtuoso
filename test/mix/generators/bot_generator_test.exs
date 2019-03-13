Code.require_file("../../support/mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Virtuoso.Gen.BotTest do
  @moduledoc """
  Tests bot generation
  """

  use ExUnit.Case
  import MixHelper
  alias Mix.Tasks.Virtuoso.Gen

  describe "run/1" do
    test "generates a basic bot with a greeting routine." do
      in_tmp('test', fn ->
        Gen.Bot.run(["GraceKelly"])

        assert_file("lib/virtuoso/bots/grace_kelly/grace_kelly.ex", fn file ->
          assert file =~ "def recipient_ids(), do: @recipient_ids"
        end)

        assert_file("lib/virtuoso/bots/grace_kelly/fast_thinking.ex", fn file ->
          assert file =~ "def run(impression), do: impression"
        end)
      end)
    end
  end
end
