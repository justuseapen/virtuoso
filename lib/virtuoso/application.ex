defmodule Virtuoso.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Virtuoso.Repo,
      # Registry + DynamicSupervisor for on-demand conversation processes.
      Virtuoso.Conversation.Supervisor,
      # Cluster-global token budget (Phase 3: fabric-supervised singleton).
      {Virtuoso.Budget, budget_opts()}
      # Subsystems attach here as they land:
      #   Virtuoso.Fabric.Supervisor     (Phase 3: Horde)
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
