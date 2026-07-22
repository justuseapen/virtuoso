defmodule Virtuoso.Thinking.SlowTest do
  use ExUnit.Case, async: true

  alias Virtuoso.{Budget, Impression}
  alias Virtuoso.Thinking.Slow

  # Routines: each returns a canned reply so we test routing, not generation.
  defmodule BookRoutine do
    @behaviour Virtuoso.Routine
    @impl true
    def run(%Impression{}, _ctx), do: {:reply, "Booked!"}
  end

  defmodule CancelRoutine do
    @behaviour Virtuoso.Routine
    @impl true
    def run(%Impression{}, _ctx), do: {:reply, "Cancelled."}
  end

  @registry %{"book" => BookRoutine, "cancel" => CancelRoutine}

  defp imp(text) do
    Impression.new(
      channel: :web_chat,
      conversation_id: "c",
      sender_id: "s",
      message_id: "m-#{System.unique_integer([:positive])}",
      text: text
    )
  end

  # An llm fn that makes every member vote `route` for the routing decision.
  defp all_vote(route) do
    fn _request, _opts ->
      {:ok, %{text: route, model: "m", stop_reason: :end_turn, usage: %{}, raw: %{}}}
    end
  end

  describe "respond/3" do
    test "routes via ensemble consensus and dispatches to the resolved routine" do
      opts = [routines: @registry, ensemble: [n: 3], llm: all_vote("book")]
      assert {:reply, "Booked!"} = Slow.respond(imp("book a flight"), %{}, opts)
    end

    test "a different consensus routes to a different routine" do
      opts = [routines: @registry, ensemble: [n: 3], llm: all_vote("cancel")]
      assert {:reply, "Cancelled."} = Slow.respond(imp("cancel it"), %{}, opts)
    end

    test "the routing request offers only the registered routine names" do
      parent = self()

      capturing = fn request, _opts ->
        send(parent, {:routing_request, request})
        {:ok, %{text: "book", model: "m", stop_reason: :end_turn, usage: %{}, raw: %{}}}
      end

      opts = [routines: @registry, ensemble: [n: 1], llm: capturing]
      Slow.respond(imp("do a thing"), %{}, opts)

      assert_received {:routing_request, request}

      body =
        Enum.map_join(request.messages, "\n", & &1.content) <> to_string(request[:system] || "")

      assert body =~ "book"
      assert body =~ "cancel"
    end

    test "an unknown/hallucinated route → defined fallback, no crash (no String.to_atom)" do
      opts = [routines: @registry, ensemble: [n: 3], llm: all_vote("nonexistent_route")]
      assert {:reply, reply} = Slow.respond(imp("weird"), %{}, opts)
      assert reply =~ "not sure" or reply =~ "help"
    end

    test "an exhausted budget short-circuits to the defined refusal message" do
      name = :"slow_budget_#{System.unique_integer([:positive])}"
      start_supervised!({Budget, name: name, per_conversation_daily: 0})

      parent = self()

      llm = fn _r, _o ->
        send(parent, :llm_called)
        {:ok, %{text: "book", model: "m", stop_reason: :end_turn, usage: %{}, raw: %{}}}
      end

      opts = [routines: @registry, ensemble: [n: 3], llm: llm, budget: name]

      assert {:reply, reply} = Slow.respond(imp("book it"), %{}, opts)
      assert reply == Budget.refusal_message()
      # The whole turn was refused — no member ever ran.
      refute_received :llm_called
    end

    test "member usage is recorded through the budget gate" do
      name = :"slow_budget_#{System.unique_integer([:positive])}"
      start_supervised!({Budget, name: name, per_conversation_daily: 1_000_000})

      llm = fn _r, _o ->
        {:ok,
         %{
           text: "book",
           model: "m",
           stop_reason: :end_turn,
           usage: %{input_tokens: 2, output_tokens: 3},
           raw: %{}
         }}
      end

      opts = [routines: @registry, ensemble: [n: 3], llm: llm, budget: name]
      the_imp = imp("book it")

      assert {:reply, "Booked!"} = Slow.respond(the_imp, %{}, opts)

      # record/3 is a cast from the member task processes — poll briefly.
      wait_until(fn -> Budget.spent(name, the_imp.conversation_id) == 15 end)
      assert Budget.spent(name, the_imp.conversation_id) == 15
    end

    test "generation is single-model: the routine runs once, not per member" do
      # Even with n:5 members voting on the route, the routine (generation) runs
      # exactly once — consensus is on the decision, not the reply.
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      opts = [
        routines: %{"book" => __MODULE__.CountingRoutine},
        ensemble: [n: 5],
        llm: all_vote("book")
      ]

      Slow.respond(imp("book"), %{counter: counter}, opts)

      assert Agent.get(counter, & &1) == 1
    end
  end

  describe "telemetry" do
    test "routing runs carry the conversation_id" do
      handler = "slow-telemetry-#{inspect(make_ref())}"
      parent = self()

      :telemetry.attach(
        handler,
        [:virtuoso, :ensemble, :run, :stop],
        fn _name, _meas, meta, _ -> send(parent, {:run_stop, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      the_imp =
        Impression.new(
          channel: :test,
          conversation_id: "slow-tel-1",
          sender_id: "u1",
          message_id: "m1",
          text: "route me"
        )

      opts = [routines: @registry, ensemble: [n: 3], llm: all_vote("book")]
      assert {:reply, "Booked!"} = Slow.respond(the_imp, %{}, opts)

      assert_received {:run_stop, meta}
      assert meta.conversation_id == "slow-tel-1"
    end
  end

  defp wait_until(fun, timeout_ms \\ 2_000) do
    do_wait(fun, System.monotonic_time(:millisecond) + timeout_ms)
  end

  defp do_wait(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        :timeout

      true ->
        Process.sleep(20)
        do_wait(fun, deadline)
    end
  end

  # A routine that increments the ctx counter, to prove single-model generation.
  defmodule CountingRoutine do
    @behaviour Virtuoso.Routine
    @impl true
    def run(%Impression{}, %{counter: counter}) do
      Agent.update(counter, &(&1 + 1))
      {:reply, "done"}
    end
  end
end
