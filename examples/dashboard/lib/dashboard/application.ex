defmodule VirtuosoDashboard.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: VirtuosoDashboard.PubSub},
      # Telemetry → ring buffer → PubSub. Must be up before traffic flows.
      VirtuosoDashboard.Collector,
      VirtuosoDashboardWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: VirtuosoDashboard.Supervisor)
  end
end
