defmodule Virtuoso.DistHelper do
  @moduledoc """
  Helpers for multi-node (`@tag :distributed`) drills.

  Peer nodes share this node's code paths (LocalCluster propagates them), so
  these functions are called on peers via `:rpc`. `start_horde/0` starts a
  Horde.Registry + Horde.DynamicSupervisor pair on the calling node, owned by a
  long-lived unlinked process (an `:rpc` call's own process exits immediately,
  which would tear down anything linked to it).
  """

  alias Horde.DynamicSupervisor, as: HordeSupervisor
  alias Virtuoso.DistHelper.Worker

  @registry Virtuoso.DistHelper.Reg
  @supervisor Virtuoso.DistHelper.Sup

  def registry, do: @registry
  def supervisor, do: @supervisor

  @doc """
  Start Horde registry + dynamic supervisor on this node (rpc-safe).

  `peers` is the explicit member list (the drill's three peer nodes) — explicit
  membership keeps the manager/test node out of the cluster and makes the drill
  deterministic, mirroring what the production fabric will configure.
  """
  def start_horde(peers) do
    registry_members = for n <- peers, do: {@registry, n}
    supervisor_members = for n <- peers, do: {@supervisor, n}

    owner =
      spawn(fn ->
        {:ok, _} =
          Horde.Registry.start_link(name: @registry, keys: :unique, members: registry_members)

        {:ok, _} =
          HordeSupervisor.start_link(
            name: @supervisor,
            strategy: :one_for_one,
            members: supervisor_members,
            process_redistribution: :active
          )

        Process.sleep(:infinity)
      end)

    wait_until(fn ->
      is_pid(Process.whereis(@registry)) and is_pid(Process.whereis(@supervisor))
    end)

    {:ok, owner}
  end

  @doc "Start a named worker under this node's Horde supervisor (rpc-safe)."
  def start_worker(key) do
    HordeSupervisor.start_child(@supervisor, Worker.child_spec(key))
  end

  @doc "Look a worker up in this node's view of the Horde registry (rpc-safe)."
  def lookup(key) do
    Horde.Registry.lookup(@registry, key)
  end

  @doc "Poll `fun` until truthy or timeout; returns elapsed ms or raises."
  def wait_until(fun, timeout_ms \\ 10_000) do
    started = System.monotonic_time(:millisecond)
    do_wait(fun, started, timeout_ms)
  end

  defp do_wait(fun, started, timeout_ms) do
    elapsed = System.monotonic_time(:millisecond) - started

    cond do
      fun.() ->
        elapsed

      elapsed > timeout_ms ->
        raise "wait_until timed out after #{timeout_ms}ms"

      true ->
        Process.sleep(50)
        do_wait(fun, started, timeout_ms)
    end
  end
end

defmodule Virtuoso.DistHelper.Worker do
  @moduledoc """
  A minimal Horde-registered worker standing in for a conversation process.
  """
  use GenServer

  alias Virtuoso.DistHelper

  def child_spec(key) do
    %{
      id: {:spike_worker, key},
      start: {__MODULE__, :start_link, [key]},
      restart: :permanent
    }
  end

  def start_link(key) do
    case GenServer.start_link(__MODULE__, key, name: via(key)) do
      {:ok, pid} ->
        {:ok, pid}

      # The documented Horde pattern: after a netsplit heals, the registry kills
      # the conflict loser, and the loser's supervisor tries to restart it — but
      # the name now belongs to the winner. Returning :ignore makes the
      # supervisor drop the child quietly instead of crash-looping. The
      # production fabric's conversation processes need this same handling.
      {:error, {:already_started, _pid}} ->
        :ignore
    end
  end

  def via(key), do: {:via, Horde.Registry, {DistHelper.registry(), key}}

  @impl true
  def init(key), do: {:ok, key}
end
