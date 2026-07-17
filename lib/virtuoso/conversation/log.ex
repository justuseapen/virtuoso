defmodule Virtuoso.Conversation.Log do
  @moduledoc """
  Append-only Postgres event log for conversations — the framework's source of
  truth.

  Every inbound message and every outbound send-intent is appended here before
  anything else acts on it. Two invariants ride on this log:

    * **Exactly-once processing.** Each event has a `dedup_key`
      (`"<channel>:<message_id>"` inbound, `"outbound:<reply_id>"` outbound) with
      a unique index. Appending a duplicate returns the existing row tagged
      `:duplicate` — a replayed webhook yields one event, and recording the
      send-intent *before* the channel send prevents double-sends on netsplit
      heal.

    * **Recovery by replay.** A conversation process rebuilds its state by
      reading `events_for/1` in insertion order — the log outlives the process
      and the node, so a crash or handoff loses at most the in-flight message.
  """

  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  alias Virtuoso.{Impression, Repo}

  @type direction :: :inbound | :outbound
  @type role :: :user | :assistant | :system
  @type append_result :: {:ok, t(), :inserted | :duplicate}

  @type t :: %__MODULE__{
          id: integer() | nil,
          conversation_id: String.t(),
          dedup_key: String.t(),
          direction: direction(),
          role: role(),
          content: String.t() | nil,
          media: map(),
          metadata: map(),
          inserted_at: DateTime.t() | nil
        }

  schema "conversation_events" do
    field(:conversation_id, :string)
    field(:dedup_key, :string)
    field(:direction, Ecto.Enum, values: [:inbound, :outbound])
    field(:role, Ecto.Enum, values: [:user, :assistant, :system])
    field(:content, :string)
    field(:media, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc """
  Append an inbound message from an `%Impression{}`. Idempotent on the
  impression's channel dedup key.
  """
  @spec append_inbound(Impression.t()) :: append_result()
  def append_inbound(%Impression{} = imp) do
    insert(%{
      conversation_id: imp.conversation_id,
      dedup_key: Impression.dedup_key(imp),
      direction: :inbound,
      role: :user,
      content: imp.text,
      media: media_map(imp.media),
      metadata: imp.metadata
    })
  end

  @doc """
  Append an outbound assistant reply, recording send-intent under
  `"outbound:<reply_id>"`. Idempotent — a second append with the same reply id
  returns the existing event, so a resend after a crash won't double-send.
  """
  @spec append_outbound(String.t(), String.t(), String.t(), map()) :: append_result()
  def append_outbound(conversation_id, reply_id, content, metadata \\ %{}) do
    insert(%{
      conversation_id: conversation_id,
      dedup_key: "outbound:#{reply_id}",
      direction: :outbound,
      role: :assistant,
      content: content,
      media: %{},
      metadata: metadata
    })
  end

  @doc "All events for a conversation, oldest first (the replay order)."
  @spec events_for(String.t()) :: [t()]
  def events_for(conversation_id) do
    Repo.all(
      from(e in __MODULE__,
        where: e.conversation_id == ^conversation_id,
        order_by: [asc: e.id]
      )
    )
  end

  @doc "Whether a dedup key has already been appended (idempotency check)."
  @spec processed?(String.t()) :: boolean()
  def processed?(dedup_key) do
    Repo.exists?(from(e in __MODULE__, where: e.dedup_key == ^dedup_key))
  end

  @doc "Total event count (test/introspection helper)."
  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(__MODULE__, :count)

  # Insert, treating a unique-violation on dedup_key as "already processed":
  # fetch and return the existing row tagged :duplicate. This is the idempotency
  # primitive the whole exactly-once story rests on.
  defp insert(attrs) do
    event = struct(__MODULE__, attrs)

    case Repo.insert(event, on_conflict: :nothing, conflict_target: :dedup_key) do
      {:ok, %__MODULE__{id: nil}} ->
        {:ok, fetch_by_dedup_key(attrs.dedup_key), :duplicate}

      {:ok, inserted} ->
        {:ok, inserted, :inserted}
    end
  end

  defp fetch_by_dedup_key(dedup_key) do
    Repo.one!(from(e in __MODULE__, where: e.dedup_key == ^dedup_key))
  end

  # Media is a list of maps in the Impression; store it under a "items" key so
  # the column stays a JSON object (Ecto :map), not a bare array.
  defp media_map([]), do: %{}
  defp media_map(media) when is_list(media), do: %{"items" => media}
end
