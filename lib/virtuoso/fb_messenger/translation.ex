defmodule Virtuoso.FbMessenger.Translation do
  @moduledoc """
  Handles translating payloads received from FB
  """

  @doc """
  Translates standard text entry
  """
  def translate_entry(%{
    "message" => %{
      "mid" => _fb_mid,
      "seq" => _seq,
      "text" => text
    },
    "recipient" => %{
      "id" => recipient_id
    },
    "sender" => %{
      "id" => sender_id
    },
    "timestamp" => _timestamp
  }) do
    %{
      message: text,
      sender_id: sender_id,
      recipient_id: recipient_id
    }
  end
end
