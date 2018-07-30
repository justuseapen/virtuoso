defmodule Medium.NetworkTest do
  use ExUnit.Case

  alias Medium.FbMessenger.Network

  test "send_messenger_response/0" do
    assert Network.send_messenger_response([]) == []
  end

  describe "send_messenger_response/1" do
  end
end
