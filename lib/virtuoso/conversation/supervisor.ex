defmodule Virtuoso.Conversation.Supervisor do
  @moduledoc """
  Supervisor for conversation processes
  """

  use Supervisor

  alias Virtuoso.Conversation
  alias Virtuoso.Conversation.Watcher

  @doc false
  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Start a new conversation
  """
  @spec start_child(Conversation.sender_id()) :: {:ok, pid}
  def start_child(sender_id) do
    child_spec = worker(Conversation, [sender_id], id: sender_id, restart: :transient)
    Supervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stop a conversation
  """
  @spec delete_child(Conversation.sender_id()) :: {:ok, pid}
  def delete_child(sender_id) do
    Supervisor.delete_child(__MODULE__, sender_id)
  end

  @doc false
  def init(_) do
    children = [
      worker(Watcher, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
