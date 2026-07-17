defmodule Virtuoso.LLM.TelemetryTest do
  use ExUnit.Case, async: true

  alias Virtuoso.LLM
  alias Virtuoso.LLM.{Error, Mock}

  @request %{model: "test-model", messages: [%{role: :user, content: "hi"}]}

  setup do
    Mock.reset()
    :ok
  end

  defp attach(event) do
    ref = make_ref()
    parent = self()
    handler = "test-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      event,
      fn name, measurements, metadata, _ ->
        send(parent, {:telemetry, name, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    ref
  end

  describe "complete/2 telemetry" do
    test "emits start and stop with model, latency, tokens, and outcome" do
      attach([:virtuoso, :llm, :complete, :start])
      attach([:virtuoso, :llm, :complete, :stop])

      Mock.expect_complete(fn _req -> {:ok, "done"} end)
      assert {:ok, _} = LLM.complete(@request, [])

      assert_received {:telemetry, [:virtuoso, :llm, :complete, :start], start_meas, start_meta}
      assert is_integer(start_meas.system_time)
      assert start_meta.model == "test-model"
      # Shape only — the raw request (messages, system prompt) must NOT leak into
      # telemetry, where any attached handler would serialize the transcript.
      refute Map.has_key?(start_meta, :request)
      assert start_meta.message_count == 1
      assert start_meta.has_system == false

      assert_received {:telemetry, [:virtuoso, :llm, :complete, :stop], stop_meas, stop_meta}
      assert is_integer(stop_meas.duration)
      assert stop_meta.model == "test-model"
      assert stop_meta.outcome == :ok
      assert stop_meta.usage == %{input_tokens: 0, output_tokens: 0}
    end

    test "emits stop with outcome :error and the error reason on a typed error" do
      attach([:virtuoso, :llm, :complete, :stop])

      Mock.expect_complete(fn _req -> {:error, Error.timeout()} end)
      assert {:error, _} = LLM.complete(@request, [])

      assert_received {:telemetry, [:virtuoso, :llm, :complete, :stop], _meas, meta}
      assert meta.outcome == :error
      assert meta.error_reason == :timeout
    end
  end

  describe "exception path" do
    test "emits :exception and re-raises when the adapter raises" do
      attach([:virtuoso, :llm, :complete, :exception])

      Mock.expect_complete(fn _req -> raise "boom" end)

      assert_raise RuntimeError, "boom", fn -> LLM.complete(@request, []) end

      assert_received {:telemetry, [:virtuoso, :llm, :complete, :exception], meas, meta}
      assert is_integer(meas.duration)
      assert meta.kind == :error
      assert %RuntimeError{message: "boom"} = meta.reason
    end
  end

  describe "stream/3 telemetry" do
    test "emits stop with the assembled outcome" do
      attach([:virtuoso, :llm, :stream, :stop])

      Mock.expect_stream(fn _req -> {:ok, ["a", "b"]} end)
      assert {:ok, _} = LLM.stream(@request, fn _ -> :ok end, [])

      assert_received {:telemetry, [:virtuoso, :llm, :stream, :stop], meas, meta}
      assert is_integer(meas.duration)
      assert meta.outcome == :ok
    end
  end
end
