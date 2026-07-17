defmodule Virtuoso.LLM do
  @moduledoc """
  The behaviour every LLM provider implements.

  This is the seam that lets the framework swap the 2018 NLP guts (Wit/Watson)
  for LLM ensembles: SlowThinking, Ensemble members, and the maker/checker
  checker all speak to this behaviour, never to a concrete provider. Tests run
  fully offline against `Virtuoso.LLM.Mock`.

  Two capabilities:

    * `complete/2` — a single non-streaming request, returning the full message.
    * `stream/2` — a streaming request; each chunk is delivered to a callback as
      it arrives. Streaming is what the user sees for generation, so first-token
      latency matters here.

  Adapters must normalize failures into `Virtuoso.LLM.Error` — never raise a
  transport exception or return a raw status. Callers pattern-match on
  `{:error, %Virtuoso.LLM.Error{reason: ...}}`.

  ## Request shape

  A `t:request/0` is a plain map:

      %{
        model: "claude-opus-4-8",
        messages: [%{role: :user, content: "hello"}],
        system: "optional system prompt",
        max_tokens: 1024,
        temperature: nil,       # adapters omit unsupported params per model
        tools: [],
        metadata: %{}
      }

  Only `:model` and `:messages` are required; adapters supply defaults for the
  rest.
  """

  alias Virtuoso.LLM.Error

  @type role :: :system | :user | :assistant
  @type message :: %{required(:role) => role(), required(:content) => String.t() | list()}

  @type request :: %{
          required(:model) => String.t(),
          required(:messages) => [message()],
          optional(:system) => String.t() | nil,
          optional(:max_tokens) => pos_integer(),
          optional(:temperature) => float() | nil,
          optional(:tools) => list(),
          optional(:metadata) => map()
        }

  @type completion :: %{
          text: String.t(),
          model: String.t(),
          stop_reason: atom() | String.t() | nil,
          usage: %{
            optional(:input_tokens) => non_neg_integer(),
            optional(:output_tokens) => non_neg_integer()
          },
          raw: map()
        }

  @type chunk :: %{delta: String.t()} | %{done: completion()}

  @doc """
  Run a single non-streaming completion.

  Returns `{:ok, completion}` or `{:error, %Virtuoso.LLM.Error{}}`. `opts` are
  adapter-level options (e.g. `:timeout`, `:api_key`) that don't belong in the
  request body.
  """
  @callback complete(request(), keyword()) :: {:ok, completion()} | {:error, Error.t()}

  @doc """
  Run a streaming completion, invoking `on_chunk` for each delta as it arrives
  and once more with the final assembled completion.

  Returns `{:ok, completion}` (the fully assembled message) or
  `{:error, %Virtuoso.LLM.Error{}}`.
  """
  @callback stream(request(), (chunk() -> any()), keyword()) ::
              {:ok, completion()} | {:error, Error.t()}

  @doc """
  The configured default adapter (`config :virtuoso, :llm, ...`).

  In test this is `Virtuoso.LLM.Mock`, keeping the suite offline.
  """
  @spec adapter() :: module()
  def adapter, do: Application.get_env(:virtuoso, :llm, Virtuoso.LLM.Anthropic)

  @doc """
  Run a completion against the configured adapter, emitting telemetry.

  Every framework LLM call goes through here, so every call is instrumented.

  ## Telemetry (public API — versioned from 0.1.0)

    * `[:virtuoso, :llm, :complete, :start]` — measurements `%{system_time}`,
      metadata `%{model, request}`.
    * `[:virtuoso, :llm, :complete, :stop]` — measurements `%{duration}` (native
      time units), metadata `%{model, outcome: :ok | :error, usage,
      error_reason}`.
    * `[:virtuoso, :llm, :complete, :exception]` — only if the adapter *raises*
      (a bug); metadata `%{model, kind, reason, stacktrace}`. The exception is
      re-raised after the event.

  `usage` carries the provider's token counts on success; `error_reason` is the
  `Virtuoso.LLM.Error` reason on failure.
  """
  @spec complete(request(), keyword()) :: {:ok, completion()} | {:error, Error.t()}
  def complete(request, opts \\ []) do
    instrument(:complete, request, fn -> adapter().complete(request, opts) end)
  end

  @doc """
  Run a streaming completion against the configured adapter, emitting telemetry.

  Emits `[:virtuoso, :llm, :stream, :start | :stop]` with the same measurement
  and metadata shape as `complete/2`.
  """
  @spec stream(request(), (chunk() -> any()), keyword()) ::
          {:ok, completion()} | {:error, Error.t()}
  def stream(request, on_chunk, opts \\ []) do
    instrument(:stream, request, fn -> adapter().stream(request, on_chunk, opts) end)
  end

  # Wrap a call in start/stop telemetry, threading the outcome into stop
  # metadata. Named span-style events so consumers can measure latency and
  # aggregate by model/outcome.
  defp instrument(op, request, fun) do
    start_time = System.monotonic_time()

    :telemetry.execute([:virtuoso, :llm, op, :start], %{system_time: System.system_time()}, %{
      model: request.model,
      request: request
    })

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:virtuoso, :llm, op, :stop],
        %{duration: duration},
        stop_metadata(request, result)
      )

      result
    catch
      # Adapters normalize errors into {:error, %Error{}}; a *raised* exception
      # is a bug, but telemetry must still close. Emit :exception, then re-raise.
      kind, reason ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:virtuoso, :llm, op, :exception],
          %{duration: duration},
          %{model: request.model, kind: kind, reason: reason, stacktrace: __STACKTRACE__}
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp stop_metadata(request, {:ok, completion}) do
    %{model: request.model, outcome: :ok, usage: completion.usage, error_reason: nil}
  end

  defp stop_metadata(request, {:error, %Error{reason: reason}}) do
    %{model: request.model, outcome: :error, usage: %{}, error_reason: reason}
  end
end
