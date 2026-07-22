defmodule VirtuosoDashboardWeb.ChatLive do
  @moduledoc """
  The showcase: a ChatGPT-like chat whose every message runs the real Virtuoso
  pipeline, beside a live "under the hood" panel fed by ensemble telemetry
  filtered to this visitor's conversation.
  """

  use Phoenix.LiveView

  alias Virtuoso.{Budget, Conversation, Impression}
  alias Virtuoso.Conversation.Log
  alias VirtuosoDashboard.Collector

  @max_input 500
  @keep_runs 8
  @transcript_window 50

  @impl true
  def mount(_params, session, socket) do
    conversation_id = Map.fetch!(session, "conversation_id")

    if connected?(socket) do
      Phoenix.PubSub.subscribe(VirtuosoDashboard.PubSub, Collector.topic())
    end

    {:ok,
     socket
     |> assign(
       conversation_id: conversation_id,
       messages: transcript(conversation_id),
       pending: false,
       runs: [],
       runs_at_send: 0
     )
     |> assign_budget()}
  end

  @impl true
  def handle_event("send", %{"chat" => %{"text" => text}}, socket) do
    text = text |> String.trim() |> String.slice(0, @max_input)

    if text == "" or socket.assigns.pending do
      {:noreply, socket}
    else
      imp =
        Impression.new(
          channel: :web,
          conversation_id: socket.assigns.conversation_id,
          sender_id: socket.assigns.conversation_id,
          message_id: "web-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false),
          text: text
        )

      responder = VirtuosoDashboard.Bot.responder()

      {:noreply,
       socket
       |> assign(pending: true, runs_at_send: length(socket.assigns.runs))
       |> update(:messages, &(&1 ++ [%{role: :user, text: text}]))
       |> start_async(:reply, fn -> Conversation.deliver(imp, responder: responder) end)}
    end
  end

  @impl true
  def handle_async(:reply, {:ok, result}, socket) do
    socket =
      case result do
        {:reply, text} -> update(socket, :messages, &(&1 ++ [%{role: :assistant, text: text}]))
        :noreply -> socket
      end

    # No new ensemble run since send → this was the deterministic fast path.
    # (The run's PubSub message beats the async result into our mailbox, so
    # this check is ordered, not racy.)
    socket =
      if length(socket.assigns.runs) == socket.assigns.runs_at_send do
        update(
          socket,
          :runs,
          &Enum.take([%{fast_path: true, at: DateTime.utc_now()} | &1], @keep_runs)
        )
      else
        socket
      end

    {:noreply, socket |> assign(pending: false) |> assign_budget()}
  end

  def handle_async(:reply, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(pending: false)
     |> update(
       :messages,
       &(&1 ++ [%{role: :assistant, text: "Something went wrong — please try again."}])
     )}
  end

  @impl true
  def handle_info({:ensemble_run, entry}, socket) do
    if entry.conversation_id == socket.assigns.conversation_id do
      {:noreply,
       socket
       |> update(:runs, &Enum.take([entry | &1], @keep_runs))
       |> assign_budget()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_call, _entry}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="chat-page">
      <section class="chat-pane">
        <h1>Virtuoso Chat</h1>
        <p class="sub">
          every message routes through a real LLM ensemble — watch it think ➔
        </p>

        <div class="messages" id="messages">
          <div :for={msg <- @messages} class={"msg #{msg.role}"}>
            <span class="who">{if msg.role == :user, do: "you", else: "virtuoso"}</span>
            <p>{msg.text}</p>
          </div>
          <div :if={@pending} class="msg assistant thinking">
            <span class="who">virtuoso</span>
            <p>thinking…</p>
          </div>
        </div>

        <form id="chat-form" phx-submit="send">
          <input
            type="text"
            name="chat[text]"
            value=""
            maxlength="500"
            placeholder="say hi, or ask anything…"
            autocomplete="off"
            disabled={@pending}
          />
          <button type="submit" disabled={@pending}>send</button>
        </form>
      </section>

      <aside class="engine-pane">
        <h2>under the hood</h2>
        <p class="sub">
          live from <code>[:virtuoso, :ensemble, :run, :stop]</code> — your
          conversation only
        </p>

        <div :for={run <- @runs} class="run-card">
          <%= if run[:fast_path] do %>
            <b class="ok">fast path</b>
            <span>deterministic match — 0 tokens, no LLM</span>
          <% else %>
            <b class={if run.outcome == :consensus, do: "ok", else: "warn"}>{run.outcome}</b>
            <span>route: <code>{run.decision || "—"}</code></span>
            <span>votes: {run.count || "–"}/{run.members_ok} · dissent: {run.dissent || 0}</span>
            <span>{run.duration_ms}ms · {tokens(run.usage)} tokens</span>
          <% end %>
        </div>
        <p :if={@runs == []} class="empty">send a message to see the ensemble vote</p>

        <h2>budget</h2>
        <div class="budget-row">
          <span>you</span> <b>{@budget.mine}</b> / {cap(@budget.mine_cap)}
        </div>
        <div class="budget-row">
          <span>everyone today</span> <b>{@budget.global}</b> / {cap(@budget.global_cap)}
        </div>
        <p class="sub">
          caps enforced by <code>Virtuoso.Budget</code> — when they're hit, the
          bot refuses politely instead of spending.
        </p>

        <p class="sub">
          <a href="https://github.com/justuseapen/virtuoso">github.com/justuseapen/virtuoso</a>
          · <a href="/dashboard">ops dashboard</a>
        </p>
      </aside>
    </div>
    """
  end

  # Rebuild the transcript from the event log (chronological) — the log
  # demoing itself across refreshes.
  defp transcript(conversation_id) do
    conversation_id
    |> Log.recent_events_for(@transcript_window)
    |> Enum.map(&%{role: role_atom(&1.role), text: &1.content})
    |> Enum.filter(&is_binary(&1.text))
  end

  defp role_atom(role) when role in [:user, "user"], do: :user
  defp role_atom(_role), do: :assistant

  defp assign_budget(socket) do
    caps = Application.get_env(:virtuoso, Virtuoso.Budget, [])

    assign(socket,
      budget: %{
        mine: Budget.spent(socket.assigns.conversation_id),
        mine_cap: Keyword.get(caps, :per_conversation_daily, :infinity),
        global: Budget.global_spent(),
        global_cap: Keyword.get(caps, :global_daily, :infinity)
      }
    )
  end

  defp tokens(%{input_tokens: i, output_tokens: o}), do: i + o
  defp tokens(_usage), do: 0

  defp cap(:infinity), do: "∞"
  defp cap(n), do: n
end
