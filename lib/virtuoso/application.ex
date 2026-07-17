defmodule Virtuoso.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Subsystems attach here as they land:
      #   Virtuoso.Repo                  (Phase 1: event log)
      #   {Registry, ...}                (Phase 1: conversation registry)
      #   Virtuoso.Budget                (Phase 1: token budget)
      #   Virtuoso.Fabric.Supervisor     (Phase 3: Horde)
    ]

    opts = [strategy: :one_for_one, name: Virtuoso.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
