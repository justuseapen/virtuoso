defmodule Virtuoso.LLM.Error do
  @moduledoc """
  A typed error from an LLM adapter.

  Adapters never leak raw HTTP status codes or transport exceptions to the rest
  of the framework — they normalize everything into this struct. The Ensemble
  consumes these *inside* member execution (dropping rate-limited/overloaded
  members, falling back below quorum) so a provider hiccup never crashes a
  conversation process.

  `reason` is the stable, matchable classification. `retryable?` tells callers
  whether a retry could plausibly succeed; `retry_after_ms` carries the
  provider's backoff hint when one is available (from the `retry-after` header).
  """

  @type reason ::
          :rate_limited
          | :overloaded
          | :timeout
          | :invalid_request
          | :unauthorized
          | :server_error
          | :unknown

  @type t :: %__MODULE__{
          reason: reason(),
          status: non_neg_integer() | nil,
          message: String.t(),
          retryable?: boolean(),
          retry_after_ms: non_neg_integer() | nil
        }

  defexception [:reason, :status, :message, :retryable?, :retry_after_ms]

  @impl true
  def message(%__MODULE__{reason: reason, message: nil}), do: "LLM error: #{reason}"
  def message(%__MODULE__{reason: reason, message: msg}), do: "LLM error (#{reason}): #{msg}"

  @doc """
  Classify an HTTP status into a typed error, reading the `retry-after` header
  (seconds) into `retry_after_ms` when present.
  """
  @spec from_status(non_neg_integer(), map(), String.t() | nil) :: t()
  def from_status(status, headers, body \\ nil)

  def from_status(429, headers, body) do
    build(:rate_limited, 429, body || "rate limited", true, retry_after_ms(headers))
  end

  def from_status(529, headers, body) do
    build(:overloaded, 529, body || "overloaded", true, retry_after_ms(headers))
  end

  def from_status(400, _headers, body) do
    build(:invalid_request, 400, body || "invalid request", false, nil)
  end

  def from_status(401, _headers, body) do
    build(:unauthorized, 401, body || "unauthorized", false, nil)
  end

  def from_status(403, _headers, body) do
    build(:unauthorized, 403, body || "forbidden", false, nil)
  end

  def from_status(status, headers, body) when status >= 500 do
    build(:server_error, status, body || "server error", true, retry_after_ms(headers))
  end

  def from_status(status, _headers, body) do
    build(:unknown, status, body || "unexpected status #{status}", false, nil)
  end

  @doc "A retryable timeout error (no HTTP status)."
  @spec timeout() :: t()
  def timeout, do: build(:timeout, nil, "request timed out", true, nil)

  @doc "Wrap an arbitrary transport failure as a non-status error."
  @spec transport(term()) :: t()
  def transport(reason),
    do: build(:unknown, nil, "transport error: #{inspect(reason)}", true, nil)

  defp build(reason, status, message, retryable?, retry_after_ms) do
    %__MODULE__{
      reason: reason,
      status: status,
      message: message,
      retryable?: retryable?,
      retry_after_ms: retry_after_ms
    }
  end

  defp retry_after_ms(headers) when is_map(headers) do
    case Map.get(headers, "retry-after") do
      nil -> nil
      value -> parse_seconds(value)
    end
  end

  defp retry_after_ms(_), do: nil

  defp parse_seconds(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, _} when seconds >= 0 -> seconds * 1000
      _ -> nil
    end
  end

  defp parse_seconds(seconds) when is_integer(seconds) and seconds >= 0, do: seconds * 1000
  defp parse_seconds(_), do: nil
end
