defmodule Virtuoso.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Virtuoso.Repo,
      # Registry + DynamicSupervisor for on-demand conversation processes.
      Virtuoso.Conversation.Supervisor
      # Subsystems attach here as they land:
      #   Virtuoso.Budget                (Phase 1: token budget)
      #   Virtuoso.Fabric.Supervisor     (Phase 3: Horde)
    ]

    opts = [strategy: :one_for_one, name: Virtuoso.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
