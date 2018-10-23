defmodule Virtuoso.Impression do
  @moduledoc """
  Internal representation of incoming messages
  """
  @enforce_keys [:sender_id, :recipient_id]
  defstruct [:message, :url, :sender_id, :recipient_id, :timestamp, :intent]

  @doc "Creates an impression of an experience to be understood and responded to"
  def build(args) do
    %__MODULE__{
      message: args[:message],
      sender_id: args[:sender_id],
      recipient_id: args[:recipient_id]
    }
  end
end
