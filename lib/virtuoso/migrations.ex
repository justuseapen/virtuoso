defmodule Virtuoso.Migrations do
  @moduledoc """
  Migrations for host applications.

  Virtuoso's conversation event log needs one table. From your app, generate a
  migration and delegate here:

      mix ecto.gen.migration add_virtuoso

      defmodule MyApp.Repo.Migrations.AddVirtuoso do
        use Ecto.Migration

        def up, do: Virtuoso.Migrations.up()
        def down, do: Virtuoso.Migrations.down()
      end

  Future schema versions will keep `up/0` idempotent-forward: it always brings a
  database to the current version.
  """

  use Ecto.Migration

  @doc "Create the conversation event log (table + dedup and replay indexes)."
  def up do
    create_if_not_exists table(:conversation_events) do
      add(:conversation_id, :string, null: false)
      add(:dedup_key, :string, null: false)
      add(:direction, :string, null: false)
      add(:role, :string, null: false)
      add(:content, :text)
      add(:media, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    # Exactly-once: the same channel message (or outbound reply id) can never be
    # appended twice.
    create_if_not_exists(unique_index(:conversation_events, [:dedup_key]))

    # Replay/recent-replay filters by conversation_id ordered by id — the
    # composite serves both as a pure index range scan.
    create_if_not_exists(index(:conversation_events, [:conversation_id, :id]))
  end

  @doc "Drop the conversation event log."
  def down do
    drop_if_exists(table(:conversation_events))
  end
end
