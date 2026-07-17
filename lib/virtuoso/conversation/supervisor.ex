defmodule Virtuoso.Conversation.Supervisor do
  @moduledoc """
  Supervises conversation processes and the registry that addresses them.

  Starts a `Registry` (keyed by conversation id) and a `DynamicSupervisor`.
  `Virtuoso.Conversation.ensure_started/1` starts a conversation on demand
  under this supervisor; a crashed conversation is simply restarted and
  rehydrates from the event log.

  In Phase 3 the registry and dynamic supervisor become their Horde equivalents
  so conversations can live anywhere in the cluster; the single-node shape here
  is the default.
  """
  use Supervisor

  @registry Virtuoso.Conversation.Registry
  @dynamic_supervisor Virtuoso.Conversation.DynamicSupervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, name: @dynamic_supervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "The registry name conversations register under."
  def registry, do: @registry

  @doc "The dynamic supervisor conversations run under."
  def dynamic_supervisor, do: @dynamic_supervisor
end
