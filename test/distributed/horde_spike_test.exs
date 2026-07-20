defmodule Virtuoso.HordeSpikeTest do
  @moduledoc """
  Phase 3 spike + scripted chaos drill (plan: "validate Horde registry
  consistency under netsplit on 3 local nodes" — the decision gate).

  Excluded by default; run with:

      mix test --include distributed test/distributed/horde_spike_test.exs

  The netsplit is simulated at Horde's membership layer (`Horde.Cluster.set_members/2`)
  rather than by severing dist connections: in a single OS process, any CRDT
  sync message transparently auto-reconnects Erlang distribution, so a
  `disconnect_node`-based split cannot be held open (and OTP 25+'s `global`
  additionally fights partial partitions). Membership partitioning exercises
  exactly the code path the decision gate cares about — the CRDT registry merge
  and its name-conflict resolution — deterministically.

  Three scenarios, timings printed for the decision-gate report:

    1. Cross-node registration visibility latency.
    2. Failover: kill the node hosting a worker → restarted elsewhere ≤ 5s.
    3. Netsplit: both sides register the same name → heal → exactly one survivor.
  """
  use ExUnit.Case, async: false

  alias Virtuoso.DistHelper

  @moduletag :distributed
  @moduletag timeout: 180_000

  setup_all do
    # epmd must be running for distribution; -daemon is a no-op if it already is.
    System.cmd("epmd", ["-daemon"])
    :ok = LocalCluster.start()
    :ok
  end

  # The drills mutate cluster state (node kills, netsplits), so each test gets a
  # FRESH 3-node cluster. It's linked to the test process, so it dies with the
  # test; the unique prefix avoids node-name collisions across tests.
  setup do
    prefix = "spike#{System.unique_integer([:positive])}"
    {:ok, cluster} = LocalCluster.start_link(3, prefix: prefix, applications: [:horde])
    {:ok, [n1, n2, n3] = nodes} = LocalCluster.nodes(cluster)

    # Bring Horde up on every peer with explicit three-peer membership.
    for n <- nodes do
      {:ok, _} = :rpc.call(n, DistHelper, :start_horde, [nodes])
    end

    # Every node's registry should report the full member set before we drill.
    DistHelper.wait_until(fn ->
      Enum.all?(nodes, fn n ->
        members = :rpc.call(n, Horde.Cluster, :members, [DistHelper.registry()])
        is_list(members) and length(members) == 3
      end)
    end)

    %{cluster: cluster, n1: n1, n2: n2, n3: n3, nodes: nodes}
  end

  test "1. registration on one node becomes visible on the others", %{n1: n1, n2: n2, n3: n3} do
    {:ok, _pid} = :rpc.call(n1, DistHelper, :start_worker, ["conv-visibility"])

    latency =
      DistHelper.wait_until(fn ->
        match?([{p, _}] when is_pid(p), :rpc.call(n2, DistHelper, :lookup, ["conv-visibility"])) and
          match?([{p, _}] when is_pid(p), :rpc.call(n3, DistHelper, :lookup, ["conv-visibility"]))
      end)

    IO.puts("\n[spike] cross-node registration visibility: #{latency}ms")
    assert latency < 5_000
  end

  test "2. killing the host node fails the worker over to a survivor ≤ 5s", %{
    cluster: cluster,
    nodes: nodes,
    n1: n1
  } do
    {:ok, _} = :rpc.call(n1, DistHelper, :start_worker, ["conv-failover"])

    # Find which node Horde placed it on, and pick a survivor to observe from.
    DistHelper.wait_until(fn ->
      match?([{p, _}] when is_pid(p), :rpc.call(n1, DistHelper, :lookup, ["conv-failover"]))
    end)

    [{pid, _}] = :rpc.call(n1, DistHelper, :lookup, ["conv-failover"])
    host = node(pid)
    observer = Enum.find(nodes, &(&1 != host))

    # Spike finding: the supervisor's child-spec CRDT syncs separately from the
    # registry entry. Killing the host before the spec reaches survivors means
    # nobody knows to restart the child. Allow several delta-CRDT sync rounds
    # (~300ms each) to settle — in production this window is covered by
    # ensure_started + rehydrate-from-log on the next deliver, so redistribution
    # is a warm-process optimization, not the recovery mechanism.
    Process.sleep(1_500)

    :ok = LocalCluster.stop(cluster, host)

    latency =
      DistHelper.wait_until(
        fn ->
          case :rpc.call(observer, DistHelper, :lookup, ["conv-failover"]) do
            [{new_pid, _}] when is_pid(new_pid) -> node(new_pid) != host
            _ -> false
          end
        end,
        15_000
      )

    [{new_pid, _}] = :rpc.call(observer, DistHelper, :lookup, ["conv-failover"])
    IO.puts("[spike] failover after node kill: #{latency}ms (#{host} → #{node(new_pid)})")
    assert latency <= 5_000, "failover took #{latency}ms (> 5s plan target)"
  end

  test "3. netsplit: same name registered on both sides → heal → exactly one survivor", %{
    n1: n1,
    n2: n2,
    n3: n3,
    nodes: nodes
  } do
    reg = DistHelper.registry()
    sup = DistHelper.supervisor()

    # Partition Horde's membership: {n1, n2} | {n3}. Each side keeps operating
    # (AP), but no CRDT sync crosses the split — the same effect a real netsplit
    # has on the registry, without fighting Erlang's transport auto-reconnect.
    :ok = :rpc.call(n1, Horde.Cluster, :set_members, [reg, [{reg, n1}, {reg, n2}]])
    :ok = :rpc.call(n1, Horde.Cluster, :set_members, [sup, [{sup, n1}, {sup, n2}]])
    :ok = :rpc.call(n3, Horde.Cluster, :set_members, [reg, [{reg, n3}]])
    :ok = :rpc.call(n3, Horde.Cluster, :set_members, [sup, [{sup, n3}]])

    DistHelper.wait_until(fn ->
      side_a = :rpc.call(n1, Horde.Cluster, :members, [reg])
      side_b = :rpc.call(n3, Horde.Cluster, :members, [reg])
      is_list(side_a) and length(side_a) == 2 and is_list(side_b) and length(side_b) == 1
    end)

    # Same conversation id claimed on both sides of the split.
    {:ok, pid_a} = :rpc.call(n1, DistHelper, :start_worker, ["conv-split"])
    {:ok, pid_b} = :rpc.call(n3, DistHelper, :start_worker, ["conv-split"])
    assert pid_a != pid_b

    # Heal: restore full membership on both sides; the CRDTs merge.
    full_reg = for n <- nodes, do: {reg, n}
    full_sup = for n <- nodes, do: {sup, n}
    :ok = :rpc.call(n1, Horde.Cluster, :set_members, [reg, full_reg])
    :ok = :rpc.call(n1, Horde.Cluster, :set_members, [sup, full_sup])
    :ok = :rpc.call(n3, Horde.Cluster, :set_members, [reg, full_reg])
    :ok = :rpc.call(n3, Horde.Cluster, :set_members, [sup, full_sup])

    # After the CRDT merge, all nodes agree on ONE registration and only one
    # of the two processes is still alive.
    latency =
      DistHelper.wait_until(
        fn ->
          views =
            for n <- [n1, n2, n3] do
              :rpc.call(n, DistHelper, :lookup, ["conv-split"])
            end

          alive =
            Enum.count([pid_a, pid_b], fn p ->
              :rpc.call(node(p), Process, :alive?, [p]) == true
            end)

          uniform? =
            case Enum.uniq(views) do
              [[{winner, _}]] when is_pid(winner) -> true
              _ -> false
            end

          uniform? and alive == 1
        end,
        30_000
      )

    IO.puts("[spike] netsplit heal → single survivor + uniform registry: #{latency}ms")

    views = for n <- [n1, n2, n3], do: :rpc.call(n, DistHelper, :lookup, ["conv-split"])
    assert [[{_winner, _}]] = Enum.uniq(views)
  end
end
