defmodule Medium.FbMessengerTest do
  use ExUnit.Case

  alias Medium.FbMessenger

  @fb_message_entries [
    %{
      "messaging" => %{
        "sender" => %{
          "id" => "<PSID>"
        },
        "recipient" => %{
          "id" => "<PAGE_ID>"
        },
        "timestamp" => 1458692752478,
        "message" => %{
          "mid" => "mid.1457764197618:41d102a3e1ae206a38",
          "text" => "hello, world!",
          "quick_reply" => %{
            "payload" => "<DEVELOPER_DEFINED_PAYLOAD>"
          }
        }
      }
    }
  ]

  describe "process_messages/1" do
    test "" do
      # FbMessenger.process_messages(@fb_message_entries)
      # ** (ArgumentError) argument error
    end
  end

  describe "start_typing_indicator/1" do
  end

  describe "stop_typing_indicator/1" do
  end
end
