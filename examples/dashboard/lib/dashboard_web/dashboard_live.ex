defmodule VirtuosoDashboardWeb.DashboardLive do
  @moduledoc """
  Dashboard v1: live ensemble runs — votes, dissent, latency, cost per decision
  — plus the LLM call stream and global budget spend, fed by the framework's
  documented telemetry through `VirtuosoDashboard.Collector`.
  """
  use Phoenix.LiveView

  alias VirtuosoDashboard.Collector

  @keep 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(VirtuosoDashboard.PubSub, Collector.topic())
    end

    recent = Collector.recent()

    {:ok,
     assign(socket,
       runs: recent.ensemble_runs,
       llm_calls: recent.llm_calls,
       budget_spent: Virtuoso.Budget.global_spent()
     )}
  end

  @impl true
  def handle_event("demo", _params, socket) do
    # Fire an offline demo ensemble (independently-noisy members, no API key
    # needed); its telemetry flows back through the collector like any real run.
    Task.Supervisor.start_child(Virtuoso.Ensemble.TaskSupervisor, fn ->
      VirtuosoDashboard.Demo.run_once()
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ensemble_run, entry}, socket) do
    {:noreply,
     assign(socket,
       runs: Enum.take([entry | socket.assigns.runs], @keep),
       budget_spent: Virtuoso.Budget.global_spent()
     )}
  end

  def handle_info({:llm_call, entry}, socket) do
    {:noreply, assign(socket, llm_calls: Enum.take([entry | socket.assigns.llm_calls], @keep))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Virtuoso — live ensemble dashboard</h1>
    <p class="sub">
      consensus runs · votes &amp; dissent · latency · cost per decision — fed by
      <code>[:virtuoso, :ensemble, :run, :stop]</code>
      and <code>[:virtuoso, :llm, *, :stop]</code>
    </p>

    <div>
      <span class="stat">global tokens spent today: <b>{@budget_spent}</b></span>
      <button phx-click="demo">Run demo ensemble (offline, 5 noisy members)</button>
    </div>

    <h2>Ensemble runs</h2>
    <table>
      <thead>
        <tr>
          <th>time</th><th>strategy</th><th>outcome</th><th>decision</th>
          <th>votes</th><th>dissent</th><th>tokens</th><th>ms</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={run <- @runs}>
          <td>{Calendar.strftime(run.at, "%H:%M:%S")}</td>
          <td>{run.strategy}</td>
          <td class={outcome_class(run.outcome)}>{run.outcome}</td>
          <td>{run.decision || "—"}</td>
          <td>{votes(run)}</td>
          <td>{run.dissent || 0}</td>
          <td>{tokens(run.usage)}</td>
          <td>{run.duration_ms}</td>
        </tr>
      </tbody>
    </table>
    <p :if={@runs == []} class="empty">no ensemble runs yet — press the demo button</p>

    <h2>LLM calls</h2>
    <table>
      <thead>
        <tr>
          <th>time</th><th>op</th><th>model</th><th>outcome</th><th>tokens</th><th>ms</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={call <- @llm_calls}>
          <td>{Calendar.strftime(call.at, "%H:%M:%S")}</td>
          <td>{call.op}</td>
          <td>{call.model}</td>
          <td class={outcome_class(call.outcome)}>{call.outcome} {call.error_reason}</td>
          <td>{tokens(call.usage)}</td>
          <td>{call.duration_ms}</td>
        </tr>
      </tbody>
    </table>
    <p :if={@llm_calls == []} class="empty">
      no direct LLM calls yet (demo members bypass the adapter seam)
    </p>
    """
  end

  defp votes(%{count: count, members_ok: ok}) when is_integer(count), do: "#{count}/#{ok}"
  defp votes(%{members_ok: ok}), do: "–/#{ok}"

  defp tokens(%{input_tokens: i, output_tokens: o}), do: i + o
  defp tokens(_), do: 0

  defp outcome_class(:consensus), do: "ok"
  defp outcome_class(:ok), do: "ok"
  defp outcome_class(:fallback), do: "warn"
  defp outcome_class(_), do: "err"
end
