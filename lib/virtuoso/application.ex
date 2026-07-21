defmodule Virtuoso.Application do
  @moduledoc false
  use Application

  alias Virtuoso.{Budget, Fabric}
  alias Virtuoso.Conversation.Supervisor, as: ConversationSupervisor

  @impl true
  def start(_type, _args) do
    # libcluster first (empty unless a topology is configured) so the cluster
    # forms before the fabric's Horde components come up on it.
    children =
      Fabric.cluster_children() ++
        repo_children() ++
        [
          # Conversation registry + dynamic supervisor, resolved through the
          # fabric (plain single-node pair by default; Horde when enabled).
          Virtuoso.Conversation.Supervisor,
          # Cluster-global token budget (fabric-supervised singleton when enabled).
          budget_child(),
          # Task supervisor for ensemble member fan-out (async_stream_nolink).
          {Task.Supervisor, name: Virtuoso.Ensemble.TaskSupervisor}
        ]

    opts = [strategy: :one_for_one, name: Virtuoso.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Consumers who only use the LLM/Ensemble layers (no conversations) can skip
  # the Postgres requirement entirely:
  #
  #     config :virtuoso, :start_repo, false
  #
  # With the repo off, Conversation/Log APIs are unavailable (they raise on
  # first use); everything else works.
  defp repo_children do
    if Application.get_env(:virtuoso, :start_repo, true), do: [Virtuoso.Repo], else: []
  end

  # Default budget caps, overridable via `config :virtuoso, Virtuoso.Budget, ...`.
  # Defaults are :infinity so the framework doesn't silently throttle a consumer
  # who hasn't opted into caps; a host app sets real limits.
  defp budget_opts do
    Application.get_env(:virtuoso, Virtuoso.Budget, [])
  end

  # Single-node: the budget is a plain local child. Fabric enabled: every node's
  # boot races to start ONE cluster-wide singleton under the Horde supervisor
  # (via-registered through the fabric registry); losers land on :ignore and are
  # dropped quietly. Anthropic limits are per-API-key, so one budget serves the
  # whole cluster.
  defp budget_child do
    if Fabric.enabled?() do
      %{
        id: Virtuoso.Budget.Starter,
        start:
          {Task, :start_link,
           [
             fn ->
               Fabric.start_child(
                 ConversationSupervisor.dynamic_supervisor(),
                 {Budget, Keyword.put(budget_opts(), :name, Budget.name())}
               )
             end
           ]},
        restart: :transient
      }
    else
      {Budget, budget_opts()}
    end
  end
end
