defmodule Virtuoso.FabricTest do
  # Not async: these tests toggle the fabric's application env.
  use ExUnit.Case, async: false

  alias Virtuoso.Fabric

  setup do
    original = Application.get_env(:virtuoso, Virtuoso.Fabric)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:virtuoso, Virtuoso.Fabric)
        value -> Application.put_env(:virtuoso, Virtuoso.Fabric, value)
      end
    end)

    :ok
  end

  describe "single-node default (zero config)" do
    test "fabric is disabled by default" do
      Application.delete_env(:virtuoso, Virtuoso.Fabric)
      refute Fabric.enabled?()
    end

    test "resolves the plain Registry/DynamicSupervisor pair" do
      Application.put_env(:virtuoso, Virtuoso.Fabric, enabled: false)
      assert Fabric.registry_module() == Registry
      assert Fabric.supervisor_module() == DynamicSupervisor
    end

    test "via tuples address the plain Registry" do
      Application.put_env(:virtuoso, Virtuoso.Fabric, enabled: false)
      assert Fabric.via(MyReg, "conv-1") == {:via, Registry, {MyReg, "conv-1"}}
    end

    test "conversation children are the plain pair" do
      Application.put_env(:virtuoso, Virtuoso.Fabric, enabled: false)
      children = Fabric.conversation_children(MyReg, MySup)

      assert [{Registry, reg_opts}, {DynamicSupervisor, sup_opts}] = children
      assert reg_opts[:name] == MyReg
      assert reg_opts[:keys] == :unique
      assert sup_opts[:name] == MySup
    end

    test "no cluster children without a topology" do
      Application.put_env(:virtuoso, Virtuoso.Fabric, enabled: false)
      assert Fabric.cluster_children() == []
    end
  end

  describe "fabric enabled" do
    setup do
      Application.put_env(:virtuoso, Virtuoso.Fabric, enabled: true)
      :ok
    end

    test "resolves the Horde pair" do
      assert Fabric.registry_module() == Horde.Registry
      assert Fabric.supervisor_module() == Horde.DynamicSupervisor
    end

    test "via tuples address Horde.Registry" do
      assert Fabric.via(MyReg, "conv-1") == {:via, Horde.Registry, {MyReg, "conv-1"}}
    end

    test "conversation children are the Horde pair with auto membership + redistribution" do
      children = Fabric.conversation_children(MyReg, MySup)

      assert [{Horde.Registry, reg_opts}, {Horde.DynamicSupervisor, sup_opts}] = children
      assert reg_opts[:members] == :auto
      assert sup_opts[:members] == :auto
      assert sup_opts[:process_redistribution] == :active
    end

    test "cluster children start libcluster when a topology is configured" do
      Application.put_env(:virtuoso, Virtuoso.Fabric,
        enabled: true,
        topologies: [gossip: [strategy: Cluster.Strategy.Gossip]]
      )

      assert [{Cluster.Supervisor, [topologies, _opts]}] = Fabric.cluster_children()
      assert Keyword.has_key?(topologies, :gossip)
    end
  end
end
