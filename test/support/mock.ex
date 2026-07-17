defmodule Virtuoso.LLM.Mock do
  @moduledoc """
  In-process `Virtuoso.LLM` adapter for tests — keeps the whole suite offline.

  Set an expectation with `expect_complete/1` or `expect_stream/1`; the mock
  runs your function against the request and shapes the result into the
  behaviour's return type. Expectations and recorded calls are scoped to the
  **calling process**, so `async: true` tests don't see each other's state.

  Script functions return the interesting part; the mock builds the envelope:

    * `expect_complete(fn req -> {:ok, "text"} end)` → `{:ok, completion}`
    * `expect_complete(fn req -> {:error, %Error{}} end)` → passed through
    * `expect_stream(fn req -> {:ok, ["chunk", "chunk"]} end)` → deltas + done
    * `expect_stream(fn req -> {:error, %Error{}} end)` → passed through

  With no expectation set, `complete/2` returns a canned response so incidental
  callers don't have to script every path.
  """

  @behaviour Virtuoso.LLM

  @table :virtuoso_llm_mock

  defp table do
    case :ets.whereis(@table) do
      :undefined ->
        # Public so callbacks running in the test process can read/write.
        :ets.new(@table, [:named_table, :public, :set])

      ref ->
        ref
    end
  end

  @doc "Clear this process's expectations and recorded calls."
  def reset do
    table()
    :ets.delete(@table, {self(), :complete})
    :ets.delete(@table, {self(), :stream})
    :ets.delete(@table, {self(), :calls})
    :ok
  end

  @doc "Script the next `complete/2` call for this process."
  def expect_complete(fun) when is_function(fun, 1) do
    table()
    :ets.insert(@table, {{self(), :complete}, fun})
    :ok
  end

  @doc "Script the next `stream/3` call for this process."
  def expect_stream(fun) when is_function(fun, 1) do
    table()
    :ets.insert(@table, {{self(), :stream}, fun})
    :ok
  end

  @doc "Requests this process has sent through the mock, oldest first."
  def calls do
    table()

    case :ets.lookup(@table, {self(), :calls}) do
      [{_, calls}] -> Enum.reverse(calls)
      [] -> []
    end
  end

  @impl true
  def complete(request, _opts) do
    record(request)

    case fetch(:complete) do
      nil -> {:ok, completion(request, "mock completion")}
      fun -> shape_complete(fun.(request), request)
    end
  end

  @impl true
  def stream(request, on_chunk, _opts) do
    record(request)

    result =
      case fetch(:stream) do
        nil -> {:ok, ["mock ", "stream"]}
        fun -> fun.(request)
      end

    case result do
      {:ok, deltas} when is_list(deltas) ->
        Enum.each(deltas, fn delta -> on_chunk.(%{delta: delta}) end)
        completion = completion(request, Enum.join(deltas))
        on_chunk.(%{done: completion})
        {:ok, completion}

      {:error, %Virtuoso.LLM.Error{}} = error ->
        error
    end
  end

  defp shape_complete({:ok, text}, request) when is_binary(text),
    do: {:ok, completion(request, text)}

  defp shape_complete({:ok, %{} = completion}, _request), do: {:ok, completion}
  defp shape_complete({:error, %Virtuoso.LLM.Error{}} = error, _request), do: error

  defp completion(request, text) do
    %{
      text: text,
      model: request.model,
      stop_reason: :end_turn,
      usage: %{input_tokens: 0, output_tokens: 0},
      raw: %{}
    }
  end

  defp fetch(kind) do
    case :ets.lookup(@table, {self(), kind}) do
      [{_, fun}] -> fun
      [] -> nil
    end
  end

  defp record(request) do
    prev =
      case :ets.lookup(@table, {self(), :calls}) do
        [{_, calls}] -> calls
        [] -> []
      end

    :ets.insert(@table, {{self(), :calls}, [request | prev]})
  end
end
