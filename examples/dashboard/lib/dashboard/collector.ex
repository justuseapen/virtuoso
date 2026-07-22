defmodule VirtuosoDashboard.Collector do
  @moduledoc """
  Bridges Virtuoso's telemetry to the dashboard.

  Attaches to the framework's documented events —
  `[:virtuoso, :ensemble, :run, :stop]` and `[:virtuoso, :llm, :complete |
  :stream, :stop]` — keeps a bounded ring of recent entries, and broadcasts each
  on the `"dashboard"` PubSub topic for the LiveView. Handlers run in the
  emitting process, so they only cast here — no work on the hot path.
  """
  use GenServer

  @topic "dashboard"
  @keep 50

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Recent entries, newest first: %{ensemble_runs: [...], llm_calls: [...]}."
  def recent, do: GenServer.call(__MODULE__, :recent)

  def topic, do: @topic

  @impl true
  def init(_opts) do
    :telemetry.attach_many(
      "virtuoso-dashboard-collector",
      [
        [:virtuoso, :ensemble, :run, :stop],
        [:virtuoso, :llm, :complete, :stop],
        [:virtuoso, :llm, :stream, :stop]
      ],
      &__MODULE__.handle_telemetry/4,
      nil
    )

    {:ok, %{ensemble_runs: [], llm_calls: []}}
  end

  @doc false
  def handle_telemetry([:virtuoso, :ensemble, :run, :stop], meas, meta, _config) do
    entry = %{
      at: DateTime.utc_now(),
      duration_ms: System.convert_time_unit(meas.duration, :native, :millisecond),
      strategy: meta.strategy |> Module.split() |> List.last(),
      outcome: meta.outcome,
      decision: meta[:decision],
      members_total: meta.members_total,
      members_ok: meta.members_ok,
      count: meta[:count],
      dissent: dissent(meta),
      usage: meta.usage,
      reason: meta[:reason],
      conversation_id: meta[:conversation_id]
    }

    GenServer.cast(__MODULE__, {:ensemble_run, entry})
  end

  def handle_telemetry([:virtuoso, :llm, op, :stop], meas, meta, _config) do
    entry = %{
      at: DateTime.utc_now(),
      op: op,
      duration_ms: System.convert_time_unit(meas.duration, :native, :millisecond),
      model: meta.model,
      outcome: meta.outcome,
      usage: meta.usage,
      error_reason: meta[:error_reason],
      conversation_id: meta[:conversation_id]
    }

    GenServer.cast(__MODULE__, {:llm_call, entry})
  end

  defp dissent(%{count: count, members_ok: ok}) when is_integer(count), do: ok - count
  defp dissent(_meta), do: nil

  @impl true
  def handle_cast({kind, entry}, state) do
    Phoenix.PubSub.broadcast(VirtuosoDashboard.PubSub, @topic, {kind, entry})

    key = if kind == :ensemble_run, do: :ensemble_runs, else: :llm_calls
    {:noreply, Map.update!(state, key, &Enum.take([entry | &1], @keep))}
  end

  @impl true
  def handle_call(:recent, _from, state), do: {:reply, state, state}
end
