defmodule Virtuoso.DataCase do
  @moduledoc """
  Test case for anything that touches the database.

  Each test runs inside a `Ecto.Adapters.SQL.Sandbox` transaction that is rolled
  back afterward, so DB-touching tests stay isolated and `async: true`-safe.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Virtuoso.Repo
      import Ecto.Query
      import Virtuoso.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Virtuoso.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
