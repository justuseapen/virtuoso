defmodule Virtuoso.Agent.LLM do
  @moduledoc """
  Behaviour for LLM providers.

  Implement this behaviour to add support for a new LLM provider.
  The framework ships with `Virtuoso.Agent.LLM.Anthropic` and
  `Virtuoso.Agent.LLM.OpenAI`.
  """

  @type message :: %{role: String.t(), content: String.t() | list()}
  @type tool_def :: map()
  @type config :: keyword()

  @type text_response :: %{type: :text, content: String.t()}
  @type tool_response :: %{type: :tool_use, tool_calls: [map()], content: list()}
  @type chat_response :: {:ok, text_response() | tool_response()} | {:error, any()}

  @doc """
  Send a list of messages to the LLM, optionally with tool definitions.

  Returns `{:ok, response}` where response indicates either a text reply
  or tool use requests.
  """
  @callback chat(messages :: [message()], tools :: [tool_def()], config :: config()) ::
              chat_response()
end
