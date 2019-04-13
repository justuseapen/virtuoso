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

        assert_file("lib/grace_kelly.ex", fn file ->
          assert file =~ "def recipient_ids(), do: @recipient_ids"
        end)

        assert_file("lib/grace_kelly/fast_thinking.ex", fn file ->
          assert file =~ "def run(impression), do: impression"
        end)

        assert_file("lib/grace_kelly/slow_thinking.ex", fn file ->
          assert file =~ "def run(impression) do"
          assert file =~ "def module_thinking do"
          assert file =~ "def module_client do"
        end)

        assert_file("lib/wit/grace_kelly/slow_thinking.ex", fn file ->
          assert file =~ "def run(impression) do"
          assert file =~ "def maybe_get_entities(%{intent: _intent} = impression), do: impression"
          assert file =~ "defp gets_entities(%{body: wit_response}) do"
        end)

        assert_file("lib/watson/grace_kelly/slow_thinking.ex", fn file ->
          assert file =~ "def run(impression) do"
          assert file =~ "defp get_conversation_session(%{sender_id: sender_id} = impression) do"
          assert file =~ "defp think_and_answer(%{message: message, session_id: session_id} = impression) do"
          assert file =~ "defp get_output(%{output: %{generic: responses, entities: entities, intents: intents}} = response, impression) do"
          assert file =~ "defp get_context(impression, %{context: %{skills:"
          assert file =~ "defp add_entities(impression, entities) do"
        end)
      end)
    end
  end
end
