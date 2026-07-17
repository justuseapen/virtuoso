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
  alias Virtuoso.Impression

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

  @doc "The pid of a conversation process, or nil if not running."
  @spec whereis(String.t()) :: pid() | nil
  def whereis(conversation_id) do
    case Registry.lookup(Supervisor.registry(), conversation_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Start (or find) the conversation process for `conversation_id`."
  @spec ensure_started(String.t()) :: pid()
  def ensure_started(conversation_id) do
    case whereis(conversation_id) do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: pid, else: start(conversation_id)

      nil ->
        start(conversation_id)
    end
  end

  defp start(conversation_id) do
    spec = {__MODULE__, conversation_id}

    case DynamicSupervisor.start_child(Supervisor.dynamic_supervisor(), spec) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
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
    GenServer.start_link(__MODULE__, conversation_id, name: via(conversation_id))
  end

  defp via(conversation_id) do
    {:via, Registry, {Supervisor.registry(), conversation_id}}
  end

  @impl true
  def init(conversation_id) do
    # Rehydrate: state is a replay of the log, not an in-memory original.
    history =
      conversation_id
      |> Log.events_for()
      |> Enum.map(&{&1.role, &1.content})

    {:ok, %{conversation_id: conversation_id, history: history}}
  end

  @impl true
  def handle_call({:deliver, imp, responder}, _from, state) do
    {:ok, _inbound, status} = Log.append_inbound(imp)

    # On a duplicate inbound, the message was already processed — don't append
    # to history a second time, but still answer the caller.
    history = maybe_append_history(state.history, {:user, imp.text}, status)

    reply = responder.(imp, state.history)

    new_state = commit_reply(reply, imp, %{state | history: history})
    {:reply, reply, new_state}
  end

  defp maybe_append_history(history, _entry, :duplicate), do: history
  defp maybe_append_history(history, entry, :inserted), do: history ++ [entry]

  defp commit_reply({:reply, text}, imp, state) do
    reply_id = "#{imp.message_id}:reply"
    {:ok, _outbound, _status} = Log.append_outbound(imp.conversation_id, reply_id, text)
    %{state | history: state.history ++ [{:assistant, text}]}
  end

  defp commit_reply(:noreply, _imp, state), do: state
end
