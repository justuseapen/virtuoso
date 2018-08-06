defmodule Virtuoso.NetworkTest do
  use ExUnit.Case

  alias Virtuoso.FbMessenger.Network

  test "send_messenger_response/0" do
    assert Network.send_messenger_response([]) == []
  end

  describe "send_messenger_response/1" do
  end
end
