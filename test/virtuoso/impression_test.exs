defmodule Virtuoso.ImpressionTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Impression

  describe "new/1" do
    test "builds a v1 envelope from the minimum required fields" do
      imp =
        Impression.new(
          channel: :web_chat,
          conversation_id: "conv-1",
          sender_id: "user-42",
          message_id: "m-100"
        )

      assert imp.version == 1
      assert imp.channel == :web_chat
      assert imp.conversation_id == "conv-1"
      assert imp.sender_id == "user-42"
      assert imp.message_id == "m-100"
      assert imp.text == nil
      assert imp.media == []
      assert imp.metadata == %{}
    end

    test "carries text, media, and metadata when supplied" do
      media = [%{type: :image, url: "https://example.test/cat.png"}]

      imp =
        Impression.new(
          channel: :web_chat,
          conversation_id: "conv-1",
          sender_id: "user-42",
          message_id: "m-101",
          text: "look at this",
          media: media,
          metadata: %{locale: "en"}
        )

      assert imp.text == "look at this"
      assert imp.media == media
      assert imp.metadata == %{locale: "en"}
    end

    test "raises when a required field is missing" do
      assert_raise ArgumentError, ~r/channel/, fn ->
        Impression.new(conversation_id: "c", sender_id: "s", message_id: "m")
      end
    end

    test "accepts a map as well as a keyword list" do
      imp =
        Impression.new(%{
          channel: :web_chat,
          conversation_id: "conv-1",
          sender_id: "user-42",
          message_id: "m-102"
        })

      assert imp.message_id == "m-102"
    end
  end

  describe "dedup_key/1" do
    test "combines channel and message id so ids are unique per channel" do
      imp =
        Impression.new(
          channel: :web_chat,
          conversation_id: "c",
          sender_id: "s",
          message_id: "m-1"
        )

      assert Impression.dedup_key(imp) == "web_chat:m-1"
    end
  end
end
