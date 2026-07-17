defmodule Virtuoso.LLM.AnthropicTest do
  use ExUnit.Case, async: true

  alias Virtuoso.LLM.{Anthropic, Error}

  @request %{
    model: "claude-opus-4-8",
    system: "You are helpful.",
    messages: [%{role: :user, content: "hello"}],
    max_tokens: 100
  }

  # Inject a canned HTTP response by giving Req a stub adapter function.
  # The adapter receives the %Req.Request{} and returns {request, %Req.Response{}}
  # (or {request, exception}) — no network, no plug dependency.
  defp stub(status, body, headers \\ %{}) do
    adapter = fn request ->
      {request, %Req.Response{status: status, body: body, headers: headers}}
    end

    [req_options: [adapter: adapter], api_key: "test-key"]
  end

  defp stub_error(exception) do
    adapter = fn request -> {request, exception} end
    [req_options: [adapter: adapter], api_key: "test-key"]
  end

  describe "complete/2 — success" do
    test "parses a text completion" do
      body = %{
        "content" => [%{"type" => "text", "text" => "hi there"}],
        "model" => "claude-opus-4-8",
        "stop_reason" => "end_turn",
        "usage" => %{"input_tokens" => 5, "output_tokens" => 2}
      }

      assert {:ok, completion} = Anthropic.complete(@request, stub(200, body))
      assert completion.text == "hi there"
      assert completion.model == "claude-opus-4-8"
      assert completion.stop_reason == :end_turn
      assert completion.usage == %{input_tokens: 5, output_tokens: 2}
    end

    test "joins multiple text blocks" do
      body = %{
        "content" => [
          %{"type" => "text", "text" => "part one"},
          %{"type" => "text", "text" => "part two"}
        ],
        "model" => "claude-opus-4-8",
        "stop_reason" => "end_turn",
        "usage" => %{}
      }

      assert {:ok, %{text: "part one\npart two"}} = Anthropic.complete(@request, stub(200, body))
    end
  end

  describe "complete/2 — request shaping" do
    test "extracts system, formats messages, and sends anthropic headers" do
      # Capture the outgoing request by asserting inside the adapter.
      parent = self()

      adapter = fn request ->
        send(parent, {:outgoing, request})

        body = %{
          "content" => [%{"type" => "text", "text" => "ok"}],
          "stop_reason" => "end_turn",
          "usage" => %{}
        }

        {request, %Req.Response{status: 200, body: body}}
      end

      opts = [req_options: [adapter: adapter], api_key: "sk-test"]
      assert {:ok, _} = Anthropic.complete(@request, opts)

      assert_received {:outgoing, req}
      # system pulled to top-level, messages carry only user/assistant
      assert req.body != nil
      decoded = Jason.decode!(req.body)
      assert decoded["system"] == "You are helpful."
      assert decoded["model"] == "claude-opus-4-8"
      assert decoded["max_tokens"] == 100
      assert decoded["messages"] == [%{"role" => "user", "content" => "hello"}]

      # required Anthropic headers
      headers = Map.new(req.headers, fn {k, v} -> {k, v} end)
      assert headers["x-api-key"] == ["sk-test"]
      assert headers["anthropic-version"] == ["2023-06-01"]
    end
  end

  describe "complete/2 — typed errors" do
    test "maps 429 to :rate_limited with retry_after" do
      assert {:error, %Error{reason: :rate_limited, retry_after_ms: 3000}} =
               Anthropic.complete(@request, stub(429, %{}, %{"retry-after" => "3"}))
    end

    test "maps 529 to :overloaded" do
      assert {:error, %Error{reason: :overloaded}} = Anthropic.complete(@request, stub(529, %{}))
    end

    test "maps 400 to :invalid_request (not retryable)" do
      assert {:error, %Error{reason: :invalid_request, retryable?: false}} =
               Anthropic.complete(@request, stub(400, %{"error" => %{"message" => "bad"}}))
    end

    test "maps a transport timeout to :timeout" do
      assert {:error, %Error{reason: :timeout}} =
               Anthropic.complete(@request, stub_error(%Req.TransportError{reason: :timeout}))
    end

    test "maps other transport errors to a retryable unknown error" do
      assert {:error, %Error{reason: :unknown, retryable?: true}} =
               Anthropic.complete(@request, stub_error(%Req.TransportError{reason: :closed}))
    end

    test "returns :unauthorized when no api key is configured" do
      assert {:error, %Error{reason: :unauthorized}} =
               Anthropic.complete(@request, api_key: nil)
    end
  end

  describe "stream/3" do
    test "delivers text deltas from SSE and assembles the completion" do
      # Anthropic SSE: content_block_delta events carry text_delta.
      sse = """
      event: message_start
      data: {"type":"message_start","message":{"model":"claude-opus-4-8"}}

      event: content_block_delta
      data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hel"}}

      event: content_block_delta
      data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"lo"}}

      event: message_delta
      data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

      event: message_stop
      data: {"type":"message_stop"}

      """

      # Stub the streamed body as a raw binary; the adapter's :into handling
      # in the adapter code parses SSE lines.
      opts = stream_stub(200, sse)

      parent = self()
      on_chunk = fn chunk -> send(parent, {:chunk, chunk}) end

      assert {:ok, completion} = Anthropic.stream(@request, on_chunk, opts)
      assert completion.text == "hello"
      assert completion.stop_reason == :end_turn

      assert_received {:chunk, %{delta: "hel"}}
      assert_received {:chunk, %{delta: "lo"}}
      assert_received {:chunk, %{done: %{text: "hello"}}}
    end

    test "propagates an error status without emitting a done chunk" do
      opts = stream_stub(429, "", %{"retry-after" => "1"})

      assert {:error, %Error{reason: :rate_limited}} =
               Anthropic.stream(@request, fn _ -> :ok end, opts)
    end
  end

  # For streaming we stub the body as the full SSE payload; the adapter parses it.
  defp stream_stub(status, sse_body, headers \\ %{}) do
    adapter = fn request ->
      {request, %Req.Response{status: status, body: sse_body, headers: headers}}
    end

    [req_options: [adapter: adapter], api_key: "test-key"]
  end
end
