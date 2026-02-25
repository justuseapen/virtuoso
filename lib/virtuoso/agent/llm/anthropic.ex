defmodule Virtuoso.Agent.LLM.Anthropic do
  @moduledoc """
  Anthropic Claude API provider for Virtuoso agents.

  ## Configuration

  Set your API key in config:

      config :virtuoso, :anthropic_api_key, "sk-ant-..."

  Or via the `ANTHROPIC_API_KEY` environment variable.

  ## Usage

      defmodule MyAgent do
        use Virtuoso.Agent,
          llm: Virtuoso.Agent.LLM.Anthropic,
          model: "claude-sonnet-4-20250514",
          max_tokens: 1024
      end
  """

  @behaviour Virtuoso.Agent.LLM

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

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
    model = Keyword.get(config, :model, "claude-sonnet-4-20250514")
    max_tokens = Keyword.get(config, :max_tokens, 1024)

    {system, messages} = extract_system(messages)

    body =
      %{
        model: model,
        max_tokens: max_tokens,
        messages: format_messages(messages)
      }
      |> maybe_add_system(system)
      |> maybe_add_tools(tools)
      |> Jason.encode!()

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]

    case HTTPoison.post(@api_url, body, headers, recv_timeout: 60_000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        parse_response(response_body)

      {:ok, %{status_code: status, body: response_body}} ->
        Logger.error("Anthropic API error (#{status}): #{response_body}")
        {:error, {:api_error, status, response_body}}

      {:error, %{reason: reason}} ->
        Logger.error("Anthropic HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp extract_system(messages) do
    case messages do
      [%{role: "system", content: system} | rest] -> {system, rest}
      _ -> {nil, messages}
    end
  end

  defp format_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} when is_binary(content) ->
        %{role: role, content: content}

      %{role: role, content: content} when is_list(content) ->
        %{role: role, content: format_content_blocks(content)}
    end)
  end

  defp format_content_blocks(blocks) do
    Enum.map(blocks, fn
      %{type: "tool_use", id: id, name: name, input: input} ->
        %{type: "tool_use", id: id, name: name, input: input}

      %{type: "tool_result", tool_use_id: id, content: content} ->
        %{type: "tool_result", tool_use_id: id, content: content}

      %{type: "text", text: text} ->
        %{type: "text", text: text}

      other ->
        other
    end)
  end

  defp maybe_add_system(body, nil), do: body
  defp maybe_add_system(body, system), do: Map.put(body, :system, system)

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) do
    formatted =
      Enum.map(tools, fn tool ->
        %{
          name: tool.name,
          description: tool.description,
          input_schema: tool.input_schema
        }
      end)

    Map.put(body, :tools, formatted)
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"content" => content, "stop_reason" => stop_reason}} ->
        parse_content(content, stop_reason)

      {:error, reason} ->
        {:error, {:json_decode_error, reason}}
    end
  end

  defp parse_content(content, "tool_use") do
    tool_calls =
      content
      |> Enum.filter(fn block -> block["type"] == "tool_use" end)
      |> Enum.map(fn block ->
        %{
          id: block["id"],
          name: block["name"],
          input: block["input"]
        }
      end)

    raw_content =
      Enum.map(content, fn
        %{"type" => "text", "text" => text} ->
          %{type: "text", text: text}

        %{"type" => "tool_use", "id" => id, "name" => name, "input" => input} ->
          %{type: "tool_use", id: id, name: name, input: input}
      end)

    {:ok, %{type: :tool_use, tool_calls: tool_calls, content: raw_content}}
  end

  defp parse_content(content, _stop_reason) do
    text =
      content
      |> Enum.filter(fn block -> block["type"] == "text" end)
      |> Enum.map(fn block -> block["text"] end)
      |> Enum.join("\n")

    {:ok, %{type: :text, content: text}}
  end

  defp api_key do
    Application.get_env(:virtuoso, :anthropic_api_key) ||
      System.get_env("ANTHROPIC_API_KEY")
  end
end
