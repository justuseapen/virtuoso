defmodule Virtuoso.Channel.WebChatTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Channel.WebChat
  alias Virtuoso.Impression

  describe "behaviour" do
    test "implements Virtuoso.Channel" do
      behaviours =
        WebChat.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

      assert Virtuoso.Channel in behaviours
    end
  end

  describe "translate_in/1" do
    test "builds a web_chat Impression from a raw web message" do
      raw = %{
        "session_id" => "sess-abc",
        "user_id" => "user-42",
        "message_id" => "m-7",
        "text" => "hello there"
      }

      assert {:ok, %Impression{} = imp} = WebChat.translate_in(raw)
      assert imp.channel == :web_chat
      assert imp.conversation_id == "sess-abc"
      assert imp.sender_id == "user-42"
      assert imp.message_id == "m-7"
      assert imp.text == "hello there"
    end

    test "derives the conversation id from the session (session-based identity)" do
      raw = %{"session_id" => "sess-xyz", "user_id" => "u", "message_id" => "m", "text" => "hi"}
      assert {:ok, %Impression{conversation_id: "sess-xyz"}} = WebChat.translate_in(raw)
    end

    test "carries metadata through" do
      raw = %{
        "session_id" => "s",
        "user_id" => "u",
        "message_id" => "m",
        "text" => "hi",
        "metadata" => %{"locale" => "en"}
      }

      assert {:ok, %Impression{metadata: %{"locale" => "en"}}} = WebChat.translate_in(raw)
    end

    test "returns an error for a payload missing required fields" do
      assert {:error, :invalid_payload} = WebChat.translate_in(%{"text" => "orphan"})
    end
  end

  describe "send_out/2" do
    test "shapes an outbound reply for the web transport" do
      imp =
        Impression.new(
          channel: :web_chat,
          conversation_id: "sess-abc",
          sender_id: "user-42",
          message_id: "m-7"
        )

      assert {:ok, payload} = WebChat.send_out(imp, "here is your answer")
      assert payload.session_id == "sess-abc"
      assert payload.text == "here is your answer"
    end
  end

  describe "verify_webhook/2" do
    test "web-chat has no webhook secret path; treated as trusted transport" do
      # Web chat authenticates via session, not webhook signatures.
      assert WebChat.verify_webhook("any", secret: nil) == :ok
    end
  end
end
