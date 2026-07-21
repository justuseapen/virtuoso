defmodule Virtuoso.Fabric do
  @moduledoc """
  The distributed compute fabric — Roemmele concept (b), as a seam.

  The fabric decides *where conversation processes live*. Disabled (the
  default), process addressing uses the plain single-node `Registry` +
  `DynamicSupervisor` and a library consumer needs **zero cluster
  configuration**. Enabled, the same names resolve through `Horde.Registry` +
  `Horde.DynamicSupervisor` (validated by the Phase 3 spike —
  `docs/spikes/2026-07-20-horde-spike-report.md`), so conversations are
  addressable cluster-wide, restart on surviving nodes when theirs dies, and
  netsplit name conflicts resolve to a single survivor on heal.

  Correctness never rests on the fabric: the event log's dedup keys are the
  exactly-once guarantee, and recovery is `ensure_started` + rehydrate-from-log
  — Horde redistribution is a warm-process optimization on top.

  ## Configuration

      # single node (default) — nothing to configure
      config :virtuoso, Virtuoso.Fabric, enabled: false

      # clustered
      config :virtuoso, Virtuoso.Fabric,
        enabled: true,
        topologies: [
          # dev: gossip; Fly.io: Cluster.Strategy.DNSPoll — any libcluster topology
          gossip: [strategy: Cluster.Strategy.Gossip]
        ]

  Fabric mode is **boot-time** configuration: the supervision tree is built from
  it at application start, so changing it at runtime has no effect until restart.
  """

  @doc "Whether the distributed fabric is enabled (default `false`)."
  @spec enabled?() :: boolean()
  def enabled?, do: Keyword.get(config(), :enabled, false)

  @doc "The registry module process addressing goes through."
  @spec registry_module() :: module()
  def registry_module, do: if(enabled?(), do: Horde.Registry, else: Registry)

  @doc "The dynamic supervisor module conversations start under."
  @spec supervisor_module() :: module()
  def supervisor_module, do: if(enabled?(), do: Horde.DynamicSupervisor, else: DynamicSupervisor)

  @doc "A via tuple for `key` in `registry_name`, through the active registry."
  @spec via(atom(), term()) :: {:via, module(), {atom(), term()}}
  def via(registry_name, key), do: {:via, registry_module(), {registry_name, key}}

  @doc "Look `key` up in `registry_name` through the active registry."
  @spec lookup(atom(), term()) :: [{pid(), term()}]
  def lookup(registry_name, key), do: registry_module().lookup(registry_name, key)

  @doc "Start `spec` under `supervisor_name` through the active supervisor."
  @spec start_child(atom(), Supervisor.child_spec() | {module(), term()} | module()) ::
          DynamicSupervisor.on_start_child()
  def start_child(supervisor_name, spec),
    do: supervisor_module().start_child(supervisor_name, spec)

  @doc """
  The registry + dynamic-supervisor children for the conversation layer, in the
  active mode. Same names either way — only the modules differ.
  """
  @spec conversation_children(atom(), atom()) :: [Supervisor.child_spec() | {module(), keyword()}]
  def conversation_children(registry_name, supervisor_name) do
    if enabled?() do
      [
        {Horde.Registry, name: registry_name, keys: :unique, members: :auto},
        {Horde.DynamicSupervisor,
         name: supervisor_name,
         strategy: :one_for_one,
         members: :auto,
         process_redistribution: :active}
      ]
    else
      [
        {Registry, keys: :unique, name: registry_name},
        {DynamicSupervisor, name: supervisor_name, strategy: :one_for_one}
      ]
    end
  end

  @doc """
  The libcluster child when a `:topologies` config is present; `[]` otherwise,
  so an unclustered deployment starts nothing extra.
  """
  @spec cluster_children() :: [Supervisor.child_spec() | {module(), list()}]
  def cluster_children do
    case Keyword.get(config(), :topologies) do
      nil -> []
      topologies -> [{Cluster.Supervisor, [topologies, [name: Virtuoso.ClusterSupervisor]]}]
    end
  end

  defp config, do: Application.get_env(:virtuoso, __MODULE__, [])
end
