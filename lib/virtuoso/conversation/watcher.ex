defmodule Virtuoso.Conversation.Watcher do
  @moduledoc """
  A watcher process for new conversations
  """

  use GenServer
  require Logger

  alias Virtuoso.Conversation
  alias Virtuoso.Conversation.Supervisor

  @doc false
  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Start watching a conversation process. When the process exits, the
  sender_id will be removed from the child spec of the supervisor,
  allowing a new process to be started.
  """
  @spec watch(pid(), Conversation.sender_id()) :: :ok
  def watch(conversation_pid, sender_id) do
    GenServer.cast(__MODULE__, {:watch, conversation_pid, sender_id})
  end

  #
  # Server
  #

  def init(_) do
    Process.flag(:trap_exit, true)
    {:ok, %{conversations: %{}}}
  end

  def handle_cast({:watch, conversation_pid, sender_id}, state) do
    Process.link(conversation_pid)
    {:noreply, put_conversation(state, conversation_pid, sender_id)}
  end

  def handle_info({:EXIT, pid, _reason}, state) do
    case Map.get(state.conversations, pid, nil) do
      nil ->
        {:noreply, state}

      sender_id ->
        delete_child(sender_id)
        {:noreply, drop_conversation(state, pid)}
    end
  end

  defp put_conversation(state, conversation_pid, sender_id) do
    %{state | conversations: Map.put(state.conversations, conversation_pid, sender_id)}
  end

  defp drop_conversation(state, pid) do
    %{state | conversations: Map.delete(state.conversations, pid)}
  end

  defp delete_child(sender_id) do
    Logger.info("Deleting child from supervisor")
    Supervisor.delete_child(sender_id)
  end
end
