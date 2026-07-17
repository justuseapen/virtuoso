defmodule Virtuoso.Channel.Signature do
  @moduledoc """
  Reusable HMAC-SHA256 webhook signature verification.

  Any channel that receives webhooks (where the transport is an unauthenticated
  public endpoint) should verify the provider's signature before trusting the
  payload — a `verify_webhook/2` implementation delegates here. The compare is
  constant-time to avoid leaking the expected signature through timing.
  """

  @doc """
  Whether `signature` is a valid HMAC-SHA256 of `payload` under `secret`.

  Accepts a bare lowercase-hex digest or a `"sha256=<hex>"`-prefixed one (the
  common webhook convention). A malformed or empty signature is simply invalid —
  never a crash.
  """
  @spec valid?(binary(), binary(), binary()) :: boolean()
  def valid?(payload, signature, secret)
      when is_binary(payload) and is_binary(signature) and is_binary(secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
    provided = strip_prefix(signature)

    # byte_size guard keeps secure_compare from being called with mismatched
    # lengths (it requires equal-length inputs); a length mismatch is invalid.
    byte_size(expected) == byte_size(provided) and secure_compare(expected, provided)
  end

  defp strip_prefix("sha256=" <> hex), do: hex
  defp strip_prefix(signature), do: signature

  # Constant-time comparison. Plug.Crypto and :crypto.hash_equals exist, but
  # keeping this dependency-free avoids pulling Plug into the library core.
  defp secure_compare(left, right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {a, b}, acc -> Bitwise.bor(acc, Bitwise.bxor(a, b)) end)
    |> Kernel.==(0)
  end
end
