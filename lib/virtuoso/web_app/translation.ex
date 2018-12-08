defmodule Virtuoso.WebApp.Translation do
  @moduledoc """
  Handles translating payloads received from Web Applications
  """
  alias Virtuoso.Impression

  @doc """
  Translates standard text entry
  """
  def translate_entry(entry) do
    uid = entry["uid"]
    text = entry["text"]

    %Impression{
      message: text,
      sender_id: uid,
      recipient_id: uid,
      timestamp: nil,
      origin: :webapp
    }
  end
end
