defmodule Virtuoso.Application do
  @moduledoc false
  use Application

  alias Virtuoso.Fabric

  @impl true
  def start(_type, _args) do
    # libcluster first (empty unless a topology is configured) so the cluster
    # forms before the fabric's Horde components come up on it.
    children =
      Fabric.cluster_children() ++
        [
          Virtuoso.Repo,
          # Conversation registry + dynamic supervisor, resolved through the
          # fabric (plain single-node pair by default; Horde when enabled).
          Virtuoso.Conversation.Supervisor,
          # Cluster-global token budget.
          {Virtuoso.Budget, budget_opts()},
          # Task supervisor for ensemble member fan-out (async_stream_nolink).
          {Task.Supervisor, name: Virtuoso.Ensemble.TaskSupervisor}
        ]

    opts = [strategy: :one_for_one, name: Virtuoso.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Default budget caps, overridable via `config :virtuoso, Virtuoso.Budget, ...`.
  # Defaults are :infinity so the framework doesn't silently throttle a consumer
  # who hasn't opted into caps; a host app sets real limits.
  defp budget_opts do
    Application.get_env(:virtuoso, Virtuoso.Budget, [])
  end
end
