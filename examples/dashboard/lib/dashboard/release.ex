defmodule VirtuosoDashboard.Release do
  @moduledoc "Release tasks — run via `bin/virtuoso_dashboard eval`."

  @doc "Bring the database to the current Virtuoso schema (Fly release_command)."
  def migrate do
    Application.ensure_all_started(:ssl)
    Application.load(:virtuoso)

    # Run the SAME migration files dev/test use (the :virtuoso app's
    # priv/repo/migrations, shipped in the release) — one schema_migrations
    # history everywhere, and future framework migrations apply automatically.
    {:ok, _fun_return, _apps} =
      Ecto.Migrator.with_repo(Virtuoso.Repo, fn repo ->
        Ecto.Migrator.run(repo, Ecto.Migrator.migrations_path(repo), :up, all: true)
      end)
  end
end
