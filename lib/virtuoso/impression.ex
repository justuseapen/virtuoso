defmodule Virtuoso.Impression do
  @moduledoc """
  Internal representation of incoming messages
  """
  @enforce_keys [:sender_id, :recipient_id]
  defstruct message: nil, url: nil, sender_id: :init, recipient_id: :init, timestamp: :timestamp, origin: :atom
end
