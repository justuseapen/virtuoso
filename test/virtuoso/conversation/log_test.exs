defmodule Virtuoso.Conversation.LogTest do
  use Virtuoso.DataCase, async: true

  alias Virtuoso.Conversation.Log
  alias Virtuoso.Impression

  defp impression(id, message_id, text) do
    Impression.new(
      channel: :web_chat,
      conversation_id: id,
      sender_id: "user-1",
      message_id: message_id,
      text: text
    )
  end

  describe "append_inbound/1" do
    test "inserts an inbound event from an impression" do
      imp = impression("conv-1", "m-1", "hello")
      assert {:ok, event, :inserted} = Log.append_inbound(imp)
      assert event.conversation_id == "conv-1"
      assert event.dedup_key == "web_chat:m-1"
      assert event.direction == :inbound
      assert event.role == :user
      assert event.content == "hello"
    end

    test "is idempotent — a duplicate channel message yields one event" do
      imp = impression("conv-1", "m-1", "hello")
      assert {:ok, event1, :inserted} = Log.append_inbound(imp)
      assert {:ok, event2, :duplicate} = Log.append_inbound(imp)
      assert event1.id == event2.id
      assert Log.count() == 1
    end
  end

  describe "append_outbound/3" do
    test "records an assistant reply with a send-intent dedup key" do
      assert {:ok, event, :inserted} =
               Log.append_outbound("conv-1", "reply-1", "hi there")

      assert event.direction == :outbound
      assert event.role == :assistant
      assert event.content == "hi there"
      assert event.dedup_key == "outbound:reply-1"
    end

    test "is idempotent on the outbound dedup key (prevents double-send)" do
      assert {:ok, _, :inserted} = Log.append_outbound("conv-1", "reply-1", "hi")
      assert {:ok, _, :duplicate} = Log.append_outbound("conv-1", "reply-1", "hi")
      assert Log.count() == 1
    end
  end

  describe "events_for/1" do
    test "replays a conversation's events in insertion order" do
      Log.append_inbound(impression("conv-1", "m-1", "one"))
      Log.append_outbound("conv-1", "r-1", "reply one")
      Log.append_inbound(impression("conv-1", "m-2", "two"))
      # different conversation — must not appear
      Log.append_inbound(impression("conv-2", "x-1", "other"))

      events = Log.events_for("conv-1")
      assert Enum.map(events, & &1.content) == ["one", "reply one", "two"]
      assert Enum.map(events, & &1.direction) == [:inbound, :outbound, :inbound]
    end

    test "returns [] for an unknown conversation" do
      assert Log.events_for("nope") == []
    end
  end

  describe "recent_events_for/2" do
    test "returns the most recent N events, oldest first" do
      for i <- 1..10, do: Log.append_inbound(impression("conv-r", "m-#{i}", "msg-#{i}"))

      recent = Log.recent_events_for("conv-r", 3)
      assert Enum.map(recent, & &1.content) == ["msg-8", "msg-9", "msg-10"]
    end

    test "returns all events when fewer than the limit exist" do
      Log.append_inbound(impression("conv-r", "m-1", "only"))
      assert Log.recent_events_for("conv-r", 100) |> Enum.map(& &1.content) == ["only"]
    end

    test "scopes to the conversation" do
      Log.append_inbound(impression("conv-a", "a1", "a"))
      Log.append_inbound(impression("conv-b", "b1", "b"))
      assert Log.recent_events_for("conv-a", 100) |> Enum.map(& &1.content) == ["a"]
    end
  end

  describe "processed?/1" do
    test "true only after the channel message has been appended" do
      imp = impression("conv-1", "m-1", "hello")
      refute Log.processed?(Impression.dedup_key(imp))
      Log.append_inbound(imp)
      assert Log.processed?(Impression.dedup_key(imp))
    end
  end
end
