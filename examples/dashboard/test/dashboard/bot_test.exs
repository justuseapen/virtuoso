defmodule VirtuosoDashboard.BotTest do
  use ExUnit.Case, async: false

  alias Virtuoso.Impression
  alias VirtuosoDashboard.Bot

  defp imp(text) do
    Impression.new(
      channel: :web,
      conversation_id: "bot-test-#{System.unique_integer([:positive])}",
      sender_id: "visitor",
      message_id: "m-#{System.unique_integer([:positive])}",
      text: text
    )
  end

  defp attach_run_stop do
    handler = "bot-test-#{inspect(make_ref())}"
    parent = self()

    :telemetry.attach(
      handler,
      [:virtuoso, :ensemble, :run, :stop],
      fn _n, _m, meta, _ -> send(parent, {:run_stop, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  test "greetings take the fast path — zero LLM calls" do
    attach_run_stop()
    assert {:reply, reply} = Bot.responder().(imp("hi"), [])
    assert reply =~ "Virtuoso"
    refute_received {:run_stop, _}
  end

  test "general questions route to answer and generate via the LLM" do
    attach_run_stop()
    assert {:reply, reply} = Bot.responder().(imp("what is the capital of france"), [])
    assert reply == "stub reply: what is the capital of france"
    assert_received {:run_stop, %{decision: "answer"}}
  end

  test "framework questions route to about_virtuoso" do
    attach_run_stop()
    assert {:reply, _} = Bot.responder().(imp("how does virtuoso vote?"), [])
    assert_received {:run_stop, %{decision: "about_virtuoso"}}
  end

  test "generation includes bounded history as messages" do
    history = [{:user, "earlier question"}, {:assistant, "earlier answer"}]
    assert {:reply, "stub reply: follow-up"} = Bot.responder().(imp("follow-up"), history)
  end

  test "a refused budget turns into the framework refusal message" do
    start_supervised!({Virtuoso.Budget, name: :bot_test_budget, global_daily: 0})
    assert {:reply, reply} = Bot.responder(budget: :bot_test_budget).(imp("anything"), [])
    assert reply == Virtuoso.Budget.refusal_message()
  end
end
