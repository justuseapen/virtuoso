defmodule Virtuoso.LLM.Anthropic do
  @moduledoc """
  Anthropic Claude adapter for `Virtuoso.LLM`, built on Req.

  Speaks the Messages API (`POST /v1/messages`). The request shape is normalized
  from `t:Virtuoso.LLM.request/0`: the system prompt is pulled to the top-level
  `system` field, and only `user`/`assistant` turns go in `messages`.

  Failures are normalized into `Virtuoso.LLM.Error` — HTTP status codes via
  `Error.from_status/3`, transport timeouts to `:timeout`, other transport
  failures to a retryable `:unknown`. The adapter never raises for an API or
  network problem.

  ## Configuration

      config :virtuoso, Virtuoso.LLM.Anthropic,
        api_key: {:system, "ANTHROPIC_API_KEY"},
        base_url: "https://api.anthropic.com"

  The API key also resolves from the `ANTHROPIC_API_KEY` env var, or from an
  `:api_key` entry in the per-call `opts`.

  ## Testing

  Pass `req_options: [adapter: fn req -> {req, %Req.Response{...}} end]` in
  `opts` to inject a canned response with no network — see the adapter's tests.
  """

  @behaviour Virtuoso.LLM

  alias Virtuoso.LLM.Error

  @api_version "2023-06-01"
  @default_base_url "https://api.anthropic.com"
  @default_max_tokens 1024
  @messages_path "/v1/messages"

  @impl true
  def complete(request, opts) do
    with {:ok, api_key} <- api_key(opts) do
      body = build_body(request, false)

      case do_request(body, api_key, opts) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          {:ok, parse_completion(response_body, request.model)}

        {:ok, %Req.Response{status: status, body: response_body, headers: headers}} ->
          {:error,
           Error.from_status(status, normalize_headers(headers), error_message(response_body))}

        {:error, exception} ->
          {:error, transport_error(exception)}
      end
    end
  end

  @impl true
  def stream(request, on_chunk, opts) do
    with {:ok, api_key} <- api_key(opts) do
      body = build_body(request, true)

      case do_request(body, api_key, opts) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          assemble_stream(response_body, request.model, on_chunk)

        {:ok, %Req.Response{status: status, body: response_body, headers: headers}} ->
          {:error,
           Error.from_status(status, normalize_headers(headers), error_message(response_body))}

        {:error, exception} ->
          {:error, transport_error(exception)}
      end
    end
  end

  # --- request building -----------------------------------------------------

  defp build_body(request, stream?) do
    {system, messages} = extract_system(request)

    %{
      model: request.model,
      max_tokens: request[:max_tokens] || @default_max_tokens,
      messages: format_messages(messages)
    }
    |> maybe_put(:system, system)
    |> maybe_put(:tools, request[:tools])
    |> maybe_put_stream(stream?)
  end

  defp extract_system(request) do
    case request[:system] do
      nil ->
        {system_from_messages(request.messages), user_messages(request.messages)}

      system ->
        {system, request.messages}
    end
  end

  defp system_from_messages(messages) do
    case messages do
      [%{role: :system, content: content} | _] -> content
      _ -> nil
    end
  end

  defp user_messages(messages), do: Enum.reject(messages, &(&1.role == :system))

  defp format_messages(messages) do
    Enum.map(messages, fn %{role: role, content: content} ->
      %{role: to_string(role), content: content}
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_stream(map, true), do: Map.put(map, :stream, true)
  defp maybe_put_stream(map, false), do: map

  # --- HTTP -----------------------------------------------------------------

  defp do_request(body, api_key, opts) do
    req_options = Keyword.get(opts, :req_options, [])

    req =
      [
        method: :post,
        base_url: base_url(opts),
        url: @messages_path,
        headers: headers(api_key),
        body: Jason.encode!(body),
        receive_timeout: Keyword.get(opts, :timeout, 60_000),
        retry: false
      ]
      |> Keyword.merge(req_options)
      |> Req.new()

    Req.request(req)
  end

  defp headers(api_key) do
    [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]
  end

  defp base_url(opts) do
    Keyword.get(opts, :base_url) || config(:base_url) || @default_base_url
  end

  # --- response parsing -----------------------------------------------------

  defp parse_completion(body, fallback_model) when is_map(body) do
    text =
      body
      |> Map.get("content", [])
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("\n", & &1["text"])

    %{
      text: text,
      model: body["model"] || fallback_model,
      stop_reason: parse_stop_reason(body["stop_reason"]),
      usage: parse_usage(body["usage"]),
      raw: body
    }
  end

  defp parse_stop_reason(nil), do: nil
  defp parse_stop_reason("end_turn"), do: :end_turn
  defp parse_stop_reason("max_tokens"), do: :max_tokens
  defp parse_stop_reason("stop_sequence"), do: :stop_sequence
  defp parse_stop_reason("tool_use"), do: :tool_use
  defp parse_stop_reason("refusal"), do: :refusal
  defp parse_stop_reason("pause_turn"), do: :pause_turn
  defp parse_stop_reason(other), do: other

  defp parse_usage(nil), do: %{}

  defp parse_usage(usage) when is_map(usage) do
    %{}
    |> put_usage(:input_tokens, usage["input_tokens"])
    |> put_usage(:output_tokens, usage["output_tokens"])
  end

  defp put_usage(map, _key, nil), do: map
  defp put_usage(map, key, value), do: Map.put(map, key, value)

  # --- streaming ------------------------------------------------------------

  # The body is the full SSE payload (Req's default when not using :into, and
  # what test stubs provide). Parse each `data:` line's JSON, emit text deltas,
  # and assemble the final completion.
  #
  # v1 limitation: this buffers the entire response before emitting deltas, so
  # `on_chunk` fires for all deltas once the body has arrived — not truly
  # incremental. Real token-by-token latency needs Req's `:into` callback to
  # feed SSE lines as they stream; wire that in when generation is connected to
  # a live channel (Phase 1 web-chat) and p95 first-token latency matters.
  defp assemble_stream(sse_body, model, on_chunk) when is_binary(sse_body) do
    {text, stop_reason, usage} =
      sse_body
      |> parse_sse_events()
      |> Enum.reduce({"", nil, %{}}, fn event, {text, stop, usage} ->
        apply_stream_event(event, text, stop, usage, on_chunk)
      end)

    completion = %{
      text: text,
      model: model,
      stop_reason: stop_reason,
      usage: usage,
      raw: %{}
    }

    on_chunk.(%{done: completion})
    {:ok, completion}
  end

  defp parse_sse_events(sse_body) do
    sse_body
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data:"))
    |> Enum.map(fn line ->
      line |> String.replace_prefix("data:", "") |> String.trim()
    end)
    |> Enum.reject(&(&1 == "" or &1 == "[DONE]"))
    |> Enum.map(&Jason.decode!/1)
  end

  defp apply_stream_event(
         %{"type" => "content_block_delta", "delta" => delta},
         text,
         stop,
         usage,
         on_chunk
       ) do
    case delta do
      %{"type" => "text_delta", "text" => chunk_text} ->
        on_chunk.(%{delta: chunk_text})
        {text <> chunk_text, stop, usage}

      _ ->
        {text, stop, usage}
    end
  end

  defp apply_stream_event(
         %{"type" => "message_delta", "delta" => delta} = event,
         text,
         stop,
         usage,
         _on_chunk
       ) do
    new_stop = parse_stop_reason(delta["stop_reason"]) || stop
    new_usage = merge_stream_usage(usage, event["usage"])
    {text, new_stop, new_usage}
  end

  defp apply_stream_event(
         %{"type" => "message_start", "message" => message},
         text,
         stop,
         usage,
         _on_chunk
       ) do
    new_usage = merge_stream_usage(usage, message["usage"])
    {text, stop, new_usage}
  end

  defp apply_stream_event(_event, text, stop, usage, _on_chunk), do: {text, stop, usage}

  defp merge_stream_usage(usage, nil), do: usage

  defp merge_stream_usage(usage, incoming) when is_map(incoming),
    do: Map.merge(usage, parse_usage(incoming))

  # --- errors & config ------------------------------------------------------

  defp api_key(opts) do
    key =
      case Keyword.fetch(opts, :api_key) do
        {:ok, value} -> value
        :error -> config(:api_key) |> resolve() || System.get_env("ANTHROPIC_API_KEY")
      end

    case key do
      nil -> {:error, Error.from_status(401, %{}, "no Anthropic API key configured")}
      key -> {:ok, key}
    end
  end

  defp resolve({:system, var}), do: System.get_env(var)
  defp resolve(value), do: value

  defp config(key), do: :virtuoso |> Application.get_env(__MODULE__, []) |> Keyword.get(key)

  defp transport_error(%Req.TransportError{reason: :timeout}), do: Error.timeout()
  defp transport_error(%Req.TransportError{reason: reason}), do: Error.transport(reason)
  defp transport_error(other), do: Error.transport(other)

  # Req delivers response headers as %{binary() => [binary()]}; flatten each
  # to a single value so Error.from_status/3 can read "retry-after" directly.
  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn
      {k, [v | _]} -> {k, v}
      {k, v} -> {k, v}
    end)
  end

  defp error_message(%{"error" => %{"message" => message}}), do: message
  defp error_message(body) when is_binary(body), do: body
  defp error_message(_), do: nil
end
