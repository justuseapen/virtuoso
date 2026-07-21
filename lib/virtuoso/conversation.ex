defmodule Virtuoso.Conversation do
  @moduledoc """
  A per-conversation process — the unit of concurrency and ordering.

  One GenServer per active conversation, addressed through the registry by
  conversation id and started on demand. Two properties fall out of the OTP
  design:

    * **FIFO ordering per conversation.** A GenServer processes its mailbox
      serially, so message #2 for a conversation cannot start until #1 finishes.
      Ordering is the actor model, not an added queue.

    * **Recovery by replay.** On start the process rebuilds its history from
      `Virtuoso.Conversation.Log`, so a crash or (in Phase 3) a node handoff
      loses at most the in-flight message. State is derived from the log, never
      the sole copy.

  `deliver/2` is the entry point: it routes the impression to the right
  conversation process (starting it if needed) and returns the reply. The reply
  itself is produced by a `:responder` function — a seam the thinking pipeline
  (FastThinking → SlowThinking) plugs into later; tests inject a deterministic
  one.
  """

  use GenServer

  alias Virtuoso.Conversation.{Log, Supervisor}
  alias Virtuoso.{Fabric, Impression}

  @typedoc "History entry as replayed from the log: {role, content}."
  @type history_entry :: {Log.role(), String.t() | nil}

  @typedoc """
  A responder turns an inbound impression + prior history into a reply.
  Returning `{:reply, text}` sends `text` back to the channel; `:noreply`
  processes the message without a reply.
  """
  @type responder :: (Impression.t(), [history_entry()] -> {:reply, String.t()} | :noreply)

  @type reply :: {:reply, String.t()} | :noreply

  # --- public API -----------------------------------------------------------

  @doc """
  Deliver an inbound impression to its conversation, returning the reply.

  Options:

    * `:responder` — the function that produces the reply (required until the
      thinking pipeline is wired in as the default).
    * `:timeout` — call timeout (default 30s).
  """
  @spec deliver(Impression.t(), keyword()) :: reply()
  def deliver(%Impression{} = imp, opts \\ []) do
    responder = Keyword.fetch!(opts, :responder)
    timeout = Keyword.get(opts, :timeout, 30_000)
    call(imp, responder, timeout, _retries = 1)
  end

  # A conversation can die between ensure_started/1 and the call (a crash, or a
  # racing kill during handoff). If the target is already gone, restart it and
  # retry once — the new process rehydrates from the log, so no state is lost.
  defp call(imp, responder, timeout, retries) do
    pid = ensure_started(imp.conversation_id)

    try do
      GenServer.call(pid, {:deliver, imp, responder}, timeout)
    catch
      :exit, {reason, _} when reason in [:noproc, :normal, :killed] and retries > 0 ->
        call(imp, responder, timeout, retries - 1)
    end
  end

  @doc """
  The pid of a conversation process, or nil if not running.

  Registry cleanup after a process death is asynchronous, so a lookup can
  briefly return a dead pid. For **local** pids we filter those out with
  `Process.alive?`; a **remote** pid (fabric enabled) can't be liveness-checked
  from here — a stale one surfaces as `:noproc` on the call, which `deliver/2`'s
  retry recovers through a rehydrating restart.
  """
  @spec whereis(String.t()) :: pid() | nil
  def whereis(conversation_id) do
    case Fabric.lookup(Supervisor.registry(), conversation_id) do
      [{pid, _}] -> if locally_dead?(pid), do: nil, else: pid
      [] -> nil
    end
  end

  defp locally_dead?(pid), do: node(pid) == node() and not Process.alive?(pid)

  @doc "Start (or find) the conversation process for `conversation_id`."
  @spec ensure_started(String.t()) :: pid()
  def ensure_started(conversation_id) do
    case whereis(conversation_id) do
      pid when is_pid(pid) -> pid
      nil -> start(conversation_id)
    end
  end

  # Bounded: the :ignore → not-found window (a dead process whose registry entry
  # hasn't been cleaned yet) resolves as soon as the registry processes the DOWN,
  # so a short backoff always suffices.
  defp start(conversation_id, attempts \\ 25) do
    if attempts == 0 do
      raise "could not start conversation #{conversation_id}: registry name unavailable"
    end

    spec = {__MODULE__, conversation_id}

    case Fabric.start_child(Supervisor.dynamic_supervisor(), spec) do
      {:ok, pid} ->
        pid

      {:error, {:already_started, pid}} ->
        pid

      # start_link mapped already_started → :ignore (see below): another process
      # holds the name — either a live winner (return it) or a dead process
      # whose registry entry is still being cleaned (back off briefly, retry).
      :ignore ->
        case whereis(conversation_id) do
          pid when is_pid(pid) ->
            pid

          nil ->
            Process.sleep(10)
            start(conversation_id, attempts - 1)
        end
    end
  end

  # --- process --------------------------------------------------------------

  @doc false
  def child_spec(conversation_id) do
    %{
      id: {__MODULE__, conversation_id},
      start: {__MODULE__, :start_link, [conversation_id]},
      restart: :transient
    }
  end

  @doc false
  def start_link(conversation_id) do
    case GenServer.start_link(__MODULE__, conversation_id, name: via(conversation_id)) do
      {:ok, pid} ->
        {:ok, pid}

      # Spike finding 3: after a netsplit heals, the registry kills the conflict
      # loser and its supervisor immediately restarts it — into a name the
      # winner now holds. Returning :ignore makes the supervisor drop the child
      # quietly instead of crash-looping. Same-node duplicate starts take this
      # path too; ensure_started/1 then resolves the winner via lookup.
      {:error, {:already_started, _pid}} ->
        :ignore
    end
  end

  defp via(conversation_id) do
    Fabric.via(Supervisor.registry(), conversation_id)
  end

  # How many recent turns to hold in process memory. The full history lives in
  # the log (the audit/replay source); process state is a bounded working window,
  # so rehydration cost and memory stay flat no matter how long a conversation
  # runs. History is kept NEWEST-FIRST internally so appends are O(1); the
  # responder receives it oldest-first via history/1.
  @history_limit 100

  @impl true
  def init(conversation_id) do
    # Rehydrate a bounded window from the log, newest-first in state.
    history =
      conversation_id
      |> Log.recent_events_for(@history_limit)
      |> Enum.reverse()
      |> Enum.map(&{&1.role, &1.content})

    {:ok, %{conversation_id: conversation_id, history: history}}
  end

  @impl true
  def handle_call({:deliver, imp, responder}, _from, state) do
    case Log.append_inbound(imp) do
      # Duplicate inbound (e.g. a replayed webhook): the message was already
      # processed. Return the reply we already sent — do NOT re-run the responder
      # (that would re-spend tokens and could return a divergent answer). State
      # is unchanged; the reply is authoritative from the log.
      {:ok, _inbound, :duplicate} ->
        {:reply, replayed_reply(imp), state}

      {:ok, _inbound, :inserted} ->
        # Responder sees history *before* this turn, oldest-first.
        reply = responder.(imp, history(state))
        state = push_history(state, {:user, imp.text})
        new_state = commit_reply(reply, imp, state)
        {:reply, reply, new_state}
    end
  end

  # Oldest-first history for the responder (state holds it newest-first).
  defp history(state), do: Enum.reverse(state.history)

  # Prepend a turn (O(1)) and cap the working window to @history_limit.
  defp push_history(state, entry) do
    %{state | history: Enum.take([entry | state.history], @history_limit)}
  end

  # The reply previously logged for this message, or :noreply if none was
  # recorded (e.g. crash after inbound-append, before the reply was committed —
  # the message is genuinely unanswered; see todo 004 / architecture P2).
  defp replayed_reply(imp) do
    case Log.fetch_outbound("#{imp.message_id}:reply") do
      %{content: text} when is_binary(text) -> {:reply, text}
      _ -> :noreply
    end
  end

  defp commit_reply({:reply, text}, imp, state) do
    reply_id = "#{imp.message_id}:reply"
    {:ok, _outbound, _status} = Log.append_outbound(imp.conversation_id, reply_id, text)
    push_history(state, {:assistant, text})
  end

  defp commit_reply(:noreply, _imp, state), do: state
end
