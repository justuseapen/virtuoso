defmodule SlackMessaging.Rtm do
  use Slack

  alias SlackMessaging.Commands

  require Logger

  def handle_connect(slack, state) do
    Logger.info("Connected as #{slack.me.name}")
    {:ok, state}
  end

  def handle_event(message = %{type: "message"}, slack, state) do
    message = handle_message_subtypes(message)

    if bot_request?(message, slack) do
      Looger.info("Incoming message for Bot ... \n#{inspect(message)}")
      text = String.replace(message.text, ~r{“|”}, "\"")

      message = Map.put(message, :text, text)

      Commands.reply(message, slack)
    end

    {:ok, state}
  end

  def handle_event(_, _, state), do: {:ok, state}

   def handle_info({:message, text, channel}, slack, state) do
     Logger.info("Sending message from handle_info")
     send_message(text, channel, slack)
     {:ok, state}
   end

   def handle_info(_, _, state), do: {:ok, state}

   defp handle_message_subtypes(data)do
     if data[:subtype] == "message_changed" do
       data
       |> Map.put(:user, data.message.user)
       |> Map.put(:text, data.message.text)
     else
       data
     end
   end

  defp bot_request?(message, slack) do
    if message[:text] && message[:user] do
       mentioned_user_id =
         message.text
         |> String.split(["<", "@", ">"], trim: true)
         |> Enum.at(0)

       mentioned_user_id == slack.me.id && slack.me.id != message.user
     else
       false
     end
  end

end
