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

  alias Ecto.Adapters.SQL.Sandbox

  setup tags do
    pid = Sandbox.start_owner!(Virtuoso.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
