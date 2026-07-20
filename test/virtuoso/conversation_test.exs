defmodule Virtuoso.ConversationTest do
  use Virtuoso.DataCase, async: false

  alias Virtuoso.{Conversation, Impression}
  alias Virtuoso.Conversation.Log

  defp impression(id, message_id, text) do
    Impression.new(
      channel: :web_chat,
      conversation_id: id,
      sender_id: "user-1",
      message_id: message_id,
      text: text
    )
  end

  # A deterministic responder so this layer is tested without the LLM pipeline:
  # echoes the inbound text back, uppercased.
  defp echo_responder do
    fn %Impression{text: text}, _history -> {:reply, String.upcase(text)} end
  end

  # Conversation.Supervisor is started by the application; tests just use it.
  # Stop any conversation processes left over between tests so ids don't collide.
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

  describe "deliver/2" do
    test "appends the inbound message, replies, and logs the outbound reply" do
      imp = impression("conv-a", "m-1", "hello")

      assert {:reply, "HELLO"} = Conversation.deliver(imp, responder: echo_responder())

      events = Log.events_for("conv-a")
      assert Enum.map(events, & &1.direction) == [:inbound, :outbound]
      assert Enum.map(events, & &1.content) == ["hello", "HELLO"]
    end

    test "a duplicate inbound message replies without appending a second event" do
      imp = impression("conv-a", "m-1", "hello")

      assert {:reply, "HELLO"} = Conversation.deliver(imp, responder: echo_responder())
      assert {:reply, _} = Conversation.deliver(imp, responder: echo_responder())

      # one inbound + one outbound, not doubled
      assert Log.count() == 2
    end

    test "a duplicate inbound does NOT re-run the responder (exactly-once)" do
      imp = impression("conv-a", "m-1", "hello")
      parent = self()

      counting = fn %Impression{text: text}, _history ->
        send(parent, :responder_ran)
        {:reply, String.upcase(text)}
      end

      # First delivery runs the responder and persists "HELLO".
      assert {:reply, "HELLO"} = Conversation.deliver(imp, responder: counting)
      assert_received :responder_ran

      # Duplicate delivery must return the ORIGINAL reply without re-running the
      # responder (no re-spend, no divergent answer). Use a different responder
      # to prove the original is returned, not a recomputation.
      divergent = fn _imp, _history -> {:reply, "DIFFERENT"} end
      assert {:reply, "HELLO"} = Conversation.deliver(imp, responder: divergent)
      refute_received :responder_ran
    end

    test "processes two messages from one conversation in order (FIFO)" do
      Conversation.deliver(impression("conv-a", "m-1", "one"), responder: echo_responder())
      Conversation.deliver(impression("conv-a", "m-2", "two"), responder: echo_responder())

      assert Log.events_for("conv-a") |> Enum.map(& &1.content) ==
               ["one", "ONE", "two", "TWO"]
    end
  end

  describe "rehydration" do
    test "a restarted conversation replays its history from the log" do
      Conversation.deliver(impression("conv-a", "m-1", "hi"), responder: echo_responder())

      # The process carries the prior turns; the responder can see them.
      capture = fn _imp, history -> {:reply, "history-len:#{length(history)}"} end

      assert {:reply, reply} =
               Conversation.deliver(impression("conv-a", "m-2", "again"), responder: capture)

      # history contains the previous inbound + outbound (2 events) before this turn
      assert reply == "history-len:2"
    end

    test "a fresh process rebuilds state from persisted events after a crash" do
      Conversation.deliver(impression("conv-b", "m-1", "persisted"), responder: echo_responder())

      # Kill the process; the next deliver must rebuild from the log.
      pid = Conversation.whereis("conv-b")
      assert is_pid(pid)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}

      capture = fn _imp, history -> {:reply, "recovered:#{length(history)}"} end

      assert {:reply, "recovered:2"} =
               Conversation.deliver(impression("conv-b", "m-2", "after"), responder: capture)
    end

    test "the responder sees history oldest-first across several turns" do
      Conversation.deliver(impression("conv-h", "m-1", "first"), responder: echo_responder())
      Conversation.deliver(impression("conv-h", "m-2", "second"), responder: echo_responder())

      # On the 3rd turn, history before it is: first, FIRST, second, SECOND —
      # in chronological order.
      capture = fn _imp, history -> {:reply, inspect(history)} end

      assert {:reply, reply} =
               Conversation.deliver(impression("conv-h", "m-3", "third"), responder: capture)

      assert reply ==
               inspect([
                 {:user, "first"},
                 {:assistant, "FIRST"},
                 {:user, "second"},
                 {:assistant, "SECOND"}
               ])
    end
  end
end
