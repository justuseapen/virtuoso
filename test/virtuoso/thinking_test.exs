defmodule Virtuoso.ThinkingTest do
  use Virtuoso.DataCase, async: false

  alias Virtuoso.{Conversation, Impression, Thinking}
  alias Virtuoso.Conversation.Log

  defmodule Greeter do
    @behaviour Virtuoso.Thinking.Fast
    @impl true
    def match(%Impression{text: text}, _ctx) do
      if String.downcase(text || "") in ["hi", "hello"],
        do: {:match, {:reply, "Hi there!"}},
        else: :no_match
    end
  end

  defmodule BookRoutine do
    @behaviour Virtuoso.Routine
    @impl true
    def run(%Impression{}, _ctx), do: {:reply, "Booked."}
  end

  defp imp(id, mid, text) do
    Impression.new(
      channel: :web_chat,
      conversation_id: id,
      sender_id: "s",
      message_id: mid,
      text: text
    )
  end

  defp responder do
    Thinking.responder(
      fast: [Greeter],
      routines: %{"book" => BookRoutine},
      ensemble: [n: 3],
      llm: fn _req, _o ->
        {:ok, %{text: "book", model: "m", stop_reason: :end_turn, usage: %{}, raw: %{}}}
      end
    )
  end

  describe "responder/1" do
    test "FastThinking handles a greeting with zero LLM calls" do
      parent = self()

      r =
        Thinking.responder(
          fast: [Greeter],
          routines: %{},
          llm: fn _req, _o ->
            send(parent, :llm_called)
            {:ok, %{text: "x", model: "m", stop_reason: :end_turn, usage: %{}, raw: %{}}}
          end
        )

      assert {:reply, "Hi there!"} = r.(imp("c", "m1", "hello"), [])
      refute_received :llm_called
    end

    test "falls through to SlowThinking (ensemble routing) when FastThinking misses" do
      assert {:reply, "Booked."} = responder().(imp("c", "m2", "I want to book a flight"), [])
    end
  end

  describe "end-to-end through Conversation" do
    setup do
      on_exit(fn ->
        Virtuoso.Conversation.DynamicSupervisor
        |> DynamicSupervisor.which_children()
        |> Enum.each(fn {_, pid, _, _} ->
          DynamicSupervisor.terminate_child(Virtuoso.Conversation.DynamicSupervisor, pid)
        end)
      end)

      :ok
    end

    test "a message flows message → thinking → reply, logged as inbound + outbound" do
      assert {:reply, "Booked."} =
               Conversation.deliver(imp("conv-x", "m-1", "book a flight"), responder: responder())

      events = Log.events_for("conv-x")
      assert Enum.map(events, & &1.direction) == [:inbound, :outbound]
      assert List.last(events).content == "Booked."
    end

    test "a greeting flows through FastThinking end-to-end" do
      assert {:reply, "Hi there!"} =
               Conversation.deliver(imp("conv-y", "m-1", "hi"), responder: responder())

      assert List.last(Log.events_for("conv-y")).content == "Hi there!"
    end
  end
end
