defmodule FbMessenger.NetworkTest do
  use ExUnit.Case

  alias FbMessenger.Network

  @message_response %{
    "messaging_type": "String",
    "recipient": %{
      "id": 320_502_891_787_948
    },
    "message": %{
      "text": "hello, world!"
    }
  }

  test "send_messenger_response/1 with no response returns an empty list" do
    assert [] = Network.send_messenger_response([])
  end

  test "send_messenger_response/1 sends a message reponse" do
    assert Network.send_messenger_response(@message_response) == :ok
  end

end
