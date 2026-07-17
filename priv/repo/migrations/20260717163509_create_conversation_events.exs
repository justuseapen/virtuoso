defmodule Virtuoso.Repo.Migrations.CreateConversationEvents do
  use Ecto.Migration

  def change do
    create table(:conversation_events) do
      add :conversation_id, :string, null: false
      add :dedup_key, :string, null: false
      add :direction, :string, null: false
      add :role, :string, null: false
      add :content, :text
      add :media, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    # Exactly-once: the same channel message can never be appended twice.
    # This is the invariant that makes duplicate-webhook replay yield one event.
    create unique_index(:conversation_events, [:dedup_key])

    # Replay reads all events for a conversation in insertion order.
    create index(:conversation_events, [:conversation_id])
  end
end
