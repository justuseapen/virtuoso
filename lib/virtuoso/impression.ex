defmodule Virtuoso.Impression do
  @moduledoc """
  The channel-neutral message envelope that flows through the framework.

  Every inbound message — from web chat, FB Messenger, or any other
  `Virtuoso.Channel` — is translated into an `%Impression{}` before it reaches
  a conversation. Adapters map their wire format *in*; the rest of the framework
  only ever sees this struct.

  The struct is **versioned** (`:version`) so state and messages survive rolling
  deploys: a node running a newer version can recognize an older envelope shape
  and upgrade it. This is v1.

  `message_id` is the channel's own id for the message. Combined with the
  channel (`dedup_key/1`) it is the idempotency key the conversation event log
  uses to guarantee exactly-one processing under at-least-once delivery.
  """

  @version 1

  @enforce_keys [:channel, :conversation_id, :sender_id, :message_id]
  defstruct version: @version,
            channel: nil,
            conversation_id: nil,
            sender_id: nil,
            message_id: nil,
            text: nil,
            media: [],
            metadata: %{}

  @type medium :: %{required(:type) => atom(), required(:url) => String.t()}

  @type t :: %__MODULE__{
          version: pos_integer(),
          channel: atom(),
          conversation_id: String.t(),
          sender_id: String.t(),
          message_id: String.t(),
          text: String.t() | nil,
          media: [medium()],
          metadata: map()
        }

  @required [:channel, :conversation_id, :sender_id, :message_id]

  @doc """
  Build a v1 impression from a keyword list or map of fields.

  `#{inspect(@required)}` are required; `:text`, `:media`, and `:metadata` are
  optional. Raises `ArgumentError` if a required field is missing.
  """
  @spec new(keyword() | map()) :: t()
  def new(fields) when is_list(fields), do: fields |> Map.new() |> new()

  def new(fields) when is_map(fields) do
    for key <- @required, not Map.has_key?(fields, key) do
      raise ArgumentError, "Virtuoso.Impression.new/1 missing required field: #{inspect(key)}"
    end

    struct!(__MODULE__, Map.put(fields, :version, @version))
  end

  @doc """
  The idempotency key for this message: `"<channel>:<message_id>"`.

  Scoping by channel keeps ids from different channels from colliding, since a
  message id is only unique within the channel that issued it.
  """
  @spec dedup_key(t()) :: String.t()
  def dedup_key(%__MODULE__{channel: channel, message_id: message_id}) do
    "#{channel}:#{message_id}"
  end
end
