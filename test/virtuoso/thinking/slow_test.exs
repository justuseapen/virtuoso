defmodule Virtuoso.Thinking.SlowTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Impression
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
