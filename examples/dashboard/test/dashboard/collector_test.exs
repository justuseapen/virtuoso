defmodule VirtuosoDashboard.CollectorTest do
  use ExUnit.Case, async: false

  alias VirtuosoDashboard.Collector

  test "ensemble entries carry the conversation_id and broadcast on PubSub" do
    Phoenix.PubSub.subscribe(VirtuosoDashboard.PubSub, Collector.topic())

    :telemetry.execute(
      [:virtuoso, :ensemble, :run, :stop],
      %{duration: System.convert_time_unit(42, :millisecond, :native)},
      %{
        strategy: Virtuoso.Ensemble.Strategy.Majority,
        outcome: :consensus,
        decision: "answer",
        members_total: 3,
        members_ok: 3,
        count: 3,
        usage: %{input_tokens: 30, output_tokens: 15},
        conversation_id: "conv-tel-1"
      }
    )

    assert_receive {:ensemble_run, entry}, 1_000
    assert entry.conversation_id == "conv-tel-1"
    assert entry.decision == "answer"
    assert entry.dissent == 0
  end
end
