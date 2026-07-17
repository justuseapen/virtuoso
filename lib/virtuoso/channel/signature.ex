defmodule Virtuoso.Channel.Signature do
  @moduledoc """
  Reusable HMAC-SHA256 webhook signature verification.

  Any channel that receives webhooks (where the transport is an unauthenticated
  public endpoint) should verify the provider's signature before trusting the
  payload — a `verify_webhook/2` implementation delegates here. The comparison
  uses `:crypto.hash_equals/2` (OTP's constant-time compare) so a wrong signature
  can't be discovered byte-by-byte through timing.
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

    # :crypto.hash_equals/2 is OTP's vetted constant-time compare (no Plug
    # dependency — :crypto is already used above). It handles unequal lengths
    # internally without a timing-distinguishable short-circuit.
    :crypto.hash_equals(expected, strip_prefix(signature))
  rescue
    # hash_equals raises on some malformed inputs; treat those as invalid.
    ArgumentError -> false
  end

  defp strip_prefix("sha256=" <> hex), do: hex
  defp strip_prefix(signature), do: signature
end
