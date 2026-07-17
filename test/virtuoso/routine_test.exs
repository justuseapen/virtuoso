defmodule Virtuoso.RoutineTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Routine

  defmodule Greeting do
    @behaviour Virtuoso.Routine
    @impl true
    def run(_impression, _context), do: {:reply, "hi"}
  end

  defmodule TimeLeft do
    @behaviour Virtuoso.Routine
    @impl true
    def run(_impression, _context), do: {:reply, "soon"}
  end

  @registry %{"greeting" => Greeting, "time_left" => TimeLeft}

  describe "fetch/2" do
    test "resolves a known routine name to its module" do
      assert {:ok, Greeting} = Routine.fetch(@registry, "greeting")
      assert {:ok, TimeLeft} = Routine.fetch(@registry, "time_left")
    end

    test "returns :error for an unknown name" do
      assert :error = Routine.fetch(@registry, "does_not_exist")
    end

    test "does NOT create an atom from external input (atom-exhaustion DoS fix)" do
      evil = "virtuoso_never_seen_atom_#{System.unique_integer([:positive])}"
      # If lookup used String.to_atom, this would create a new atom.
      assert :error = Routine.fetch(@registry, evil)

      assert_raise ArgumentError, fn -> String.to_existing_atom(evil) end
    end

    test "a non-string name is a miss, not a crash" do
      assert :error = Routine.fetch(@registry, nil)
      assert :error = Routine.fetch(@registry, 123)
    end
  end

  describe "dispatch/4" do
    test "runs the resolved routine" do
      assert {:reply, "hi"} = Routine.dispatch(@registry, "greeting", :imp, %{})
    end

    test "returns {:error, :unknown_routine} for an unknown name" do
      assert {:error, :unknown_routine} = Routine.dispatch(@registry, "nope", :imp, %{})
    end
  end
end
