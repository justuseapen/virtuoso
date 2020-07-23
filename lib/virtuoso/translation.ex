defmodule Virtuoso.Translation do
  @moduledoc """
  Handles translating payloads received from FB
  """
  alias Virtuoso.Impression

  @doc """
  Translates standard text entry
  """
  def translate_entry(%{
        "message" => %{
          "attachments" => [
            %{
              "payload" => %{
                "sticker_id" => _sticker_id,
                "url" => url
              },
              "type" => "image"
            }
          ],
          "mid" => _fb_message_id,
          "sticker_id" => _sticker_id
        },
        "recipient" => %{"id" => recipient_id},
        "sender" => %{"id" => sender_id},
        "timestamp" => timestamp
      }) do
    %Impression{
      url: url,
      sender_id: sender_id,
      recipient_id: recipient_id,
      timestamp: timestamp
    }
  end

  @doc """
    This is translation for debug messages
  """
  def translate_entry(%{
        "message" => %{
          "text" => text
        },
        "recipient" => %{
          "id" => recipient_id
        },
        "sender" => %{
          "id" => sender_id
        },
        "timestamp" => timestamp,
        "debug" => debug
      }) do
    %Impression{
      message: text,
      sender_id: sender_id,
      recipient_id: recipient_id,
      timestamp: timestamp,
      debug: debug
    }
  end

  def translate_entry(%{
        "message" => %{
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
    %Impression{
      message: text,
      sender_id: sender_id,
      recipient_id: recipient_id,
      timestamp: timestamp
    }
  end
end
