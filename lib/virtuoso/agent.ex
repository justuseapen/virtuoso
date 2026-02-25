defmodule Virtuoso.Agent do
  @moduledoc """
  Behaviour and orchestration for modern LLM-powered agents.

  An agent uses a large language model (like Claude or GPT) to reason about
  user messages and optionally invoke tools to take actions. This replaces the
  traditional FastThinking → SlowThinking → Routine pipeline with a single
  LLM-driven loop.

  ## Usage

      defmodule MyApp.Agent.Assistant do
        use Virtuoso.Agent,
          llm: Virtuoso.Agent.LLM.Anthropic,
          model: "claude-sonnet-4-20250514"

        @impl true
        def system_prompt do
          "You are a helpful assistant."
        end

        @impl true
        def tools do
          [MyApp.Agent.Tools.Weather]
        end
      end

  Then in your bot module:

      defmodule MyApp.Bot do
        def respond_to(impression, conversation_state) do
          Virtuoso.Agent.respond(MyApp.Agent.Assistant, impression, conversation_state)
        end
      end
  """

  require Logger

  @max_tool_depth 10

  @doc "Returns the system prompt for this agent."
  @callback system_prompt() :: String.t()

  @doc "Returns a list of tool modules available to this agent."
  @callback tools() :: [module()]

  @doc "Returns the LLM provider module."
  @callback llm_provider() :: module()

  @doc "Returns provider-specific configuration (model, temperature, etc)."
  @callback llm_config() :: keyword()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Virtuoso.Agent

      @llm_provider Keyword.get(opts, :llm, Virtuoso.Agent.LLM.Anthropic)
      @llm_model Keyword.get(opts, :model, "claude-sonnet-4-20250514")
      @llm_max_tokens Keyword.get(opts, :max_tokens, 1024)

      @impl true
      def tools, do: []

      @impl true
      def llm_provider, do: @llm_provider

      @impl true
      def llm_config do
        [model: @llm_model, max_tokens: @llm_max_tokens]
      end

      defoverridable tools: 0, llm_provider: 0, llm_config: 0
    end
  end

  @doc """
  Sends an impression through the agent's LLM with tool use support.

  Builds a message history from the conversation state, sends it to the LLM
  provider, and handles any tool calls in a loop until the agent produces a
  final text response.
  """
  def respond(agent_module, impression, conversation_state) do
    messages =
      Virtuoso.Agent.Conversation.build_messages(
        agent_module.system_prompt(),
        conversation_state,
        impression
      )

    tool_defs =
      agent_module.tools()
      |> Enum.map(& &1.definition())

    provider = agent_module.llm_provider()
    config = agent_module.llm_config()

    run_loop(provider, config, messages, tool_defs, agent_module, impression)
  end

  defp run_loop(provider, config, messages, tool_defs, agent_module, impression, depth \\ 0) do
    tools_arg = if tool_defs == [], do: [], else: tool_defs

    case provider.chat(messages, tools_arg, config) do
      {:ok, %{type: :text, content: text}} ->
        text

      {:ok, %{type: :tool_use, tool_calls: calls, content: raw_content}} ->
        tool_results = execute_tools(calls, agent_module.tools(), impression)

        updated_messages =
          messages ++
            [
              %{role: "assistant", content: raw_content},
              %{role: "user", content: tool_results}
            ]

        if depth < @max_tool_depth do
          run_loop(provider, config, updated_messages, tool_defs, agent_module, impression, depth + 1)
        else
          Logger.warning("Agent hit max tool depth (#{@max_tool_depth})")
          extract_text_from_content(raw_content) || "I wasn't able to complete the request."
        end

      {:error, reason} ->
        Logger.error("Agent LLM error: #{inspect(reason)}")
        "I'm sorry, I encountered an error processing your request."
    end
  end

  defp execute_tools(calls, tool_modules, impression) do
    tool_map =
      tool_modules
      |> Enum.map(fn mod -> {mod.name(), mod} end)
      |> Map.new()

    Enum.map(calls, fn %{id: id, name: name, input: input} ->
      context = %{impression: impression}

      result =
        case Map.get(tool_map, name) do
          nil ->
            "Error: Unknown tool '#{name}'"

          mod ->
            case mod.execute(input, context) do
              {:ok, output} -> output
              {:error, error} -> "Error: #{error}"
            end
        end

      %{type: "tool_result", tool_use_id: id, content: result}
    end)
  end

  defp extract_text_from_content(content) when is_list(content) do
    content
    |> Enum.find_value(fn
      %{type: "text", text: text} -> text
      _ -> nil
    end)
  end

  defp extract_text_from_content(_), do: nil
end
