defmodule Virtuoso.Repo.Migrations.CompositeConversationIndex do
  use Ecto.Migration

  # Replace the single-column conversation_id index with a composite
  # (conversation_id, id): replay (and bounded recent-replay) filters by
  # conversation_id and orders by id, so the composite serves both the lookup
  # and the sort as a pure index range scan — no separate sort step. The
  # composite also covers the prefix lookup the single-column index did.
  def change do
    drop index(:conversation_events, [:conversation_id])
    create index(:conversation_events, [:conversation_id, :id])
  end
end
