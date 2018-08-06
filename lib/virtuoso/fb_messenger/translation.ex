defmodule Virtuoso.FbMessenger.Translation do
  @moduledoc """
  Handles translating payloads received from FB
  """

  @doc """
  Translates standard text entry
  """
  def translate_entry(%{
    "message" => %{
      "mid" => fb_mid,
      "seq" => seq,
      "text" => text
    },
    "recipient" => %{
      "id" => recipient_id
    },
    "sender" => %{
      "id" => sender_id
    },
    "timestamp" => timestamp
  }) do
    %{
      message: text,
      sender_id: sender_id,
      recipient_id: recipient_id
    }
  end
end
