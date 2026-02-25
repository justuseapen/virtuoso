defmodule Virtuoso.Agent.LLM.OpenAI do
  @moduledoc """
  OpenAI API provider for Virtuoso agents.

  ## Configuration

  Set your API key in config:

      config :virtuoso, :openai_api_key, "sk-..."

  Or via the `OPENAI_API_KEY` environment variable.

  ## Usage

      defmodule MyAgent do
        use Virtuoso.Agent,
          llm: Virtuoso.Agent.LLM.OpenAI,
          model: "gpt-4o"
      end
  """

  @behaviour Virtuoso.Agent.LLM

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"

  @impl true
  def chat(messages, tools, config) do
    api_key = api_key()

    if is_nil(api_key) do
      {:error, :missing_api_key}
    else
      do_chat(messages, tools, config, api_key)
    end
  end

  defp do_chat(messages, tools, config, api_key) do
    model = Keyword.get(config, :model, "gpt-4o")
    max_tokens = Keyword.get(config, :max_tokens, 1024)

    body =
      %{
        model: model,
        max_tokens: max_tokens,
        messages: format_messages(messages)
      }
      |> maybe_add_tools(tools)
      |> Jason.encode!()

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.post(@api_url, body, headers, recv_timeout: 60_000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        parse_response(response_body)

      {:ok, %{status_code: status, body: response_body}} ->
        Logger.error("OpenAI API error (#{status}): #{response_body}")
        {:error, {:api_error, status, response_body}}

      {:error, %{reason: reason}} ->
        Logger.error("OpenAI HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp format_messages(messages) do
    Enum.map(messages, fn
      %{role: "system", content: content} when is_binary(content) ->
        %{role: "system", content: content}

      %{role: role, content: content} when is_binary(content) ->
        %{role: role, content: content}

      %{role: "assistant", content: content} when is_list(content) ->
        # Convert Anthropic-style tool_use blocks to OpenAI tool_calls
        text_parts =
          content
          |> Enum.filter(fn block -> match?(%{type: "text"}, block) end)
          |> Enum.map(fn %{text: text} -> text end)
          |> Enum.join("\n")

        tool_calls =
          content
          |> Enum.filter(fn block -> match?(%{type: "tool_use"}, block) end)
          |> Enum.map(fn %{id: id, name: name, input: input} ->
            %{
              id: id,
              type: "function",
              function: %{name: name, arguments: Jason.encode!(input)}
            }
          end)

        msg = %{role: "assistant", content: text_parts}

        if tool_calls != [] do
          Map.put(msg, :tool_calls, tool_calls)
        else
          msg
        end

      %{role: "user", content: content} when is_list(content) ->
        # Convert tool_result blocks to OpenAI tool messages
        tool_results =
          content
          |> Enum.filter(fn block -> match?(%{type: "tool_result"}, block) end)

        if tool_results != [] do
          # OpenAI wants separate messages per tool result
          Enum.map(tool_results, fn %{tool_use_id: id, content: result} ->
            %{role: "tool", tool_call_id: id, content: result}
          end)
        else
          [%{role: "user", content: content}]
        end
    end)
    |> List.flatten()
  end

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) do
    formatted =
      Enum.map(tools, fn tool ->
        %{
          type: "function",
          function: %{
            name: tool.name,
            description: tool.description,
            parameters: tool.input_schema
          }
        }
      end)

    Map.put(body, :tools, formatted)
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"choices" => [%{"message" => message} | _]}} ->
        parse_message(message)

      {:error, reason} ->
        {:error, {:json_decode_error, reason}}
    end
  end

  defp parse_message(%{"tool_calls" => tool_calls} = message) when is_list(tool_calls) do
    calls =
      Enum.map(tool_calls, fn tc ->
        %{
          id: tc["id"],
          name: tc["function"]["name"],
          input: Jason.decode!(tc["function"]["arguments"])
        }
      end)

    text = message["content"] || ""

    raw_content =
      [%{type: "text", text: text}] ++
        Enum.map(calls, fn %{id: id, name: name, input: input} ->
          %{type: "tool_use", id: id, name: name, input: input}
        end)

    {:ok, %{type: :tool_use, tool_calls: calls, content: raw_content}}
  end

  defp parse_message(%{"content" => content}) do
    {:ok, %{type: :text, content: content || ""}}
  end

  defp api_key do
    Application.get_env(:virtuoso, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY")
  end
end
