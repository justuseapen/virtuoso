defmodule VirtuosoDashboard.Release do
  @moduledoc "Release tasks — run via `bin/virtuoso_dashboard eval`."

  @doc "Bring the database to the current Virtuoso schema (Fly release_command)."
  def migrate do
    Application.ensure_all_started(:ssl)
    Application.load(:virtuoso)

    {:ok, _fun_return, _apps} =
      Ecto.Migrator.with_repo(Virtuoso.Repo, fn repo ->
        Ecto.Migrator.run(repo, [{20_260_722_000_000, Virtuoso.Migrations}], :up, all: true)
      end)
  end
end
