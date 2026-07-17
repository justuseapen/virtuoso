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

  @doc "Convenience: `complete/2` against the configured default adapter."
  @spec complete(request(), keyword()) :: {:ok, completion()} | {:error, Error.t()}
  def complete(request, opts \\ []), do: adapter().complete(request, opts)

  @doc "Convenience: `stream/3` against the configured default adapter."
  @spec stream(request(), (chunk() -> any()), keyword()) ::
          {:ok, completion()} | {:error, Error.t()}
  def stream(request, on_chunk, opts \\ []), do: adapter().stream(request, on_chunk, opts)
end
