defmodule Virtuoso.Channel.SignatureTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Channel.Signature

  @secret "shhh-webhook-secret"
  @payload ~s({"event":"message","text":"hello"})

  defp sign(payload, secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  describe "valid?/3" do
    test "accepts a correct hex-encoded HMAC-SHA256 signature" do
      sig = sign(@payload, @secret)
      assert Signature.valid?(@payload, sig, @secret)
    end

    test "accepts a 'sha256=' prefixed signature (common webhook convention)" do
      sig = "sha256=" <> sign(@payload, @secret)
      assert Signature.valid?(@payload, sig, @secret)
    end

    test "rejects a tampered payload" do
      sig = sign(@payload, @secret)
      refute Signature.valid?(@payload <> "x", sig, @secret)
    end

    test "rejects a signature made with the wrong secret" do
      sig = sign(@payload, "wrong-secret")
      refute Signature.valid?(@payload, sig, @secret)
    end

    test "rejects a malformed (non-hex) signature without crashing" do
      refute Signature.valid?(@payload, "not-a-hex-signature", @secret)
    end

    test "rejects an empty signature" do
      refute Signature.valid?(@payload, "", @secret)
    end
  end
end
