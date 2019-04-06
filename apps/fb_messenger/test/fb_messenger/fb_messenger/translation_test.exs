defmodule FbMessenger.TranslationTest do
  use ExUnit.Case

  alias FbMessenger.Translation
  alias FbMessenger.Impression

  @entry %{
    "message" => %{
      "mid" => "mid.1460620432888:f8e3412003d2d1cd93",
      "seq" => 12_604,
      "text" => "Hi there!"
    },
    "recipient" => %{"id" => 320_502_891_787_948},
    "sender" => %{"id" => 722_502_891_787_948},
    "timestamp" => 1_460_220_433_123
  }

  @entry_with_attachments %{
    "message" => %{
      "attachments" => [
        %{
          "payload" => %{
            "sticker_id" => 800_002_891_787_948,
            "url" => "http://www.messenger-rocks.com/image.jpg"
          },
          "type" => "image"
        }
      ],
      "mid" => 200_002_891_787_948,
      "sticker_id" => 800_002_891_787_948
    },
    "recipient" => %{"id" => 100_002_891_787_948},
    "sender" => %{"id" => 600_202_891_787_948},
    "timestamp" => 1_460_620_433_123
  }

  test "translate_entry/1 translates an entry" do
    assert %Impression{
      message: text,
      sender_id: sender_id,
      recipient_id: recipient_id,
      timestamp: timestamp
    } = Translation.translate_entry(@entry)

    assert text == "Hi there!"
    assert recipient_id == 320_502_891_787_948
    assert sender_id == 722_502_891_787_948
    assert timestamp == 1_460_220_433_123
  end

  test "translate_entry/1 translates an entry with attachments" do
    assert %Impression{
      url: url,
      sender_id: sender_id,
      recipient_id: recipient_id,
      timestamp: timestamp
    } = Translation.translate_entry(@entry_with_attachments)

    assert url == "http://www.messenger-rocks.com/image.jpg"
    assert recipient_id == 100_002_891_787_948
    assert sender_id == 600_202_891_787_948
    assert timestamp == 1_460_620_433_123
  end

end
