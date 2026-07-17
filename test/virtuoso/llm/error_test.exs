defmodule Virtuoso.LLM.ErrorTest do
  use ExUnit.Case, async: true

  alias Virtuoso.LLM.Error

  describe "from_status/2" do
    test "maps 429 to :rate_limited and carries retry_after" do
      err = Error.from_status(429, %{"retry-after" => "12"})
      assert err.reason == :rate_limited
      assert err.retryable?
      assert err.retry_after_ms == 12_000
    end

    test "maps 529 to :overloaded" do
      err = Error.from_status(529, %{})
      assert err.reason == :overloaded
      assert err.retryable?
    end

    test "maps 400 to :invalid_request and is not retryable" do
      err = Error.from_status(400, %{})
      assert err.reason == :invalid_request
      refute err.retryable?
    end

    test "maps 401 to :unauthorized and is not retryable" do
      err = Error.from_status(401, %{})
      assert err.reason == :unauthorized
      refute err.retryable?
    end

    test "maps unknown 5xx to :server_error and is retryable" do
      err = Error.from_status(503, %{})
      assert err.reason == :server_error
      assert err.retryable?
    end
  end

  describe "timeout/0" do
    test "builds a retryable timeout error" do
      err = Error.timeout()
      assert err.reason == :timeout
      assert err.retryable?
    end
  end

  test "is an Elixir exception with a message" do
    err = Error.from_status(429, %{})
    assert Exception.message(err) =~ "rate_limited"
  end
end
