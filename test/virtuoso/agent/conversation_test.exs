defmodule Virtuoso.Agent.ConversationTest do
  use ExUnit.Case

  alias Virtuoso.Agent.Conversation
  alias Virtuoso.Impression

  test "build_messages with empty history" do
    impression = %Impression{
      sender_id: "user_1",
      recipient_id: "bot_1",
      message: "Hello"
    }

    messages = Conversation.build_messages("You are helpful.", %{messages: []}, impression)

    assert [
             %{role: "system", content: "You are helpful."},
             %{role: "user", content: "Hello"}
           ] == messages
  end

  test "build_messages with conversation history" do
    previous_impression = %Impression{
      sender_id: "user_1",
      recipient_id: "bot_1",
      message: "Hi"
    }

    previous_response = %{text: "Hello! How can I help?"}

    impression = %Impression{
      sender_id: "user_1",
      recipient_id: "bot_1",
      message: "What's the weather?"
    }

    # Messages are stored newest-first in conversation state
    conversation_state = %{messages: [previous_response, previous_impression]}

    messages = Conversation.build_messages("System prompt.", conversation_state, impression)

    assert [
             %{role: "system", content: "System prompt."},
             %{role: "user", content: "Hi"},
             %{role: "assistant", content: "Hello! How can I help?"},
             %{role: "user", content: "What's the weather?"}
           ] == messages
  end

  test "build_messages handles nil conversation state" do
    impression = %Impression{
      sender_id: "user_1",
      recipient_id: "bot_1",
      message: "Test"
    }

    messages = Conversation.build_messages("Prompt.", nil, impression)

    assert [
             %{role: "system", content: "Prompt."},
             %{role: "user", content: "Test"}
           ] == messages
  end

  test "build_messages handles string responses in history" do
    impression = %Impression{
      sender_id: "user_1",
      recipient_id: "bot_1",
      message: "Follow up"
    }

    conversation_state = %{messages: ["Previous bot reply"]}

    messages = Conversation.build_messages("Sys.", conversation_state, impression)

    assert [
             %{role: "system", content: "Sys."},
             %{role: "assistant", content: "Previous bot reply"},
             %{role: "user", content: "Follow up"}
           ] == messages
  end
end
