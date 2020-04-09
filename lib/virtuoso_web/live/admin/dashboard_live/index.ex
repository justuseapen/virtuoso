defmodule VirtuosoWeb.Admin.DashboardLive.Index do
  use Phoenix.LiveView
  alias VirtuosoWeb.Admin.DashboardView
  alias Virtuoso.Admin.Dashboard

  def mount(_params, _session, socket) do
    bots = Dashboard.list_bots()
    chat_messages = []

    {:ok, assign(socket, bots: bots, chat_messages: chat_messages)}
  end

  def render(assigns) do
    DashboardView.render("index.html", assigns)
  end

  def handle_event(
        "send_message",
        %{"chat_message" => %{"bot" => bot, "message" => message}},
        socket
      ) do
    chat_messages = [%{user: "Msg", message: message} | socket.assigns.chat_messages]

    params = %{
      "entry" => %{
        "messaging" => %{
          "debug" => false,
          "message" => %{"text" => message},
          "recipient" => %{"id" => bot},
          "sender" => %{"id" => "999999"},
          "timestamp" => ""
        }
      },
      "object" => ""
    }

    response = Poison.encode!(Dashboard.send_message(params), pretty: true)
    chat_messages = [%{user: bot, message: response} | chat_messages]
    {:noreply, assign(socket, chat_messages: Enum.reverse(chat_messages))}
  end
end
