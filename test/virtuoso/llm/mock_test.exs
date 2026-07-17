defmodule Virtuoso.LLM.MockTest do
  use ExUnit.Case, async: true

  alias Virtuoso.LLM.{Error, Mock}

  @request %{model: "test-model", messages: [%{role: :user, content: "hi"}]}

  setup do
    Mock.reset()
    :ok
  end

  test "implements the Virtuoso.LLM behaviour" do
    behaviours = Mock.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()
    assert Virtuoso.LLM in behaviours
  end

  describe "complete/2" do
    test "returns a scripted text completion" do
      Mock.expect_complete(fn _req -> {:ok, "hello there"} end)
      assert {:ok, completion} = Mock.complete(@request, [])
      assert completion.text == "hello there"
      assert completion.model == "test-model"
      assert completion.stop_reason == :end_turn
    end

    test "returns a scripted typed error" do
      Mock.expect_complete(fn _req -> {:error, Error.timeout()} end)
      assert {:error, %Error{reason: :timeout}} = Mock.complete(@request, [])
    end

    test "records the requests it received" do
      Mock.expect_complete(fn _req -> {:ok, "ok"} end)
      Mock.complete(@request, [])
      assert [%{model: "test-model"}] = Mock.calls()
    end

    test "the script function receives the request" do
      Mock.expect_complete(fn req -> {:ok, "echo: #{hd(req.messages).content}"} end)
      assert {:ok, %{text: "echo: hi"}} = Mock.complete(@request, [])
    end

    test "defaults to a canned response when no expectation is set" do
      assert {:ok, %{text: text}} = Mock.complete(@request, [])
      assert is_binary(text)
    end
  end

  describe "stream/3" do
    test "invokes the callback per delta and returns the assembled completion" do
      Mock.expect_stream(fn _req -> {:ok, ["hel", "lo"]} end)

      parent = self()
      on_chunk = fn chunk -> send(parent, {:chunk, chunk}) end

      assert {:ok, completion} = Mock.stream(@request, on_chunk, [])
      assert completion.text == "hello"

      assert_received {:chunk, %{delta: "hel"}}
      assert_received {:chunk, %{delta: "lo"}}
      assert_received {:chunk, %{done: %{text: "hello"}}}
    end

    test "propagates a scripted error without invoking the callback with a done chunk" do
      Mock.expect_stream(fn _req -> {:error, Error.from_status(429, %{})} end)
      assert {:error, %Error{reason: :rate_limited}} = Mock.stream(@request, fn _ -> :ok end, [])
    end
  end
end
