defmodule SlackMessaging.Commands do

  # TODO: use regex to match input and reply with appropriate response.
  def reply(message, slack) do
    case message["text"] do
      "hello" -> "world"
      _ -> "Hi"

    end
  end

end
