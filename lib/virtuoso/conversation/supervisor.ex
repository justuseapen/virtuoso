defmodule Virtuoso.Conversation.Supervisor do
  @moduledoc """
  Supervises conversation processes and the registry that addresses them.

  The registry/supervisor pair comes from `Virtuoso.Fabric`: the plain
  single-node `Registry` + `DynamicSupervisor` by default, or the Horde
  equivalents when the fabric is enabled — in which case conversations are
  addressable cluster-wide and restart on surviving nodes. Either way,
  `Virtuoso.Conversation.ensure_started/1` starts a conversation on demand, and
  a restarted conversation rehydrates from the event log.
  """
  use Supervisor

  alias Virtuoso.Fabric

  @registry Virtuoso.Conversation.Registry
  @dynamic_supervisor Virtuoso.Conversation.DynamicSupervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Plain Registry/DynamicSupervisor single-node, the Horde pair when the
    # fabric is enabled — same names either way. :rest_for_one so a registry
    # crash also restarts the dynamic supervisor whose children hold now-dangling
    # via-registrations.
    children = Fabric.conversation_children(@registry, @dynamic_supervisor)
    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "The registry name conversations register under."
  def registry, do: @registry

  @doc "The dynamic supervisor conversations run under."
  def dynamic_supervisor, do: @dynamic_supervisor
end
