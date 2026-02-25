defmodule Virtuoso.AgentTest do
  use ExUnit.Case

  alias Virtuoso.Impression

  # A mock LLM that returns a canned text response
  defmodule MockLLM do
    @behaviour Virtuoso.Agent.LLM

    @impl true
    def chat(_messages, _tools, _config) do
      {:ok, %{type: :text, content: "Hello from the agent!"}}
    end
  end

  # A mock LLM that requests a tool call then responds with text
  defmodule MockLLMWithTools do
    @behaviour Virtuoso.Agent.LLM

    @impl true
    def chat(messages, _tools, _config) do
      # If the conversation already has a tool result, return text
      has_tool_result =
        Enum.any?(messages, fn
          %{role: "user", content: content} when is_list(content) ->
            Enum.any?(content, fn
              %{type: "tool_result"} -> true
              _ -> false
            end)

          _ ->
            false
        end)

      if has_tool_result do
        {:ok, %{type: :text, content: "The greeting is: Hello, World!"}}
      else
        {:ok,
         %{
           type: :tool_use,
           tool_calls: [
             %{id: "call_123", name: "get_greeting", input: %{"name" => "World"}}
           ],
           content: [
             %{type: "text", text: "Let me get a greeting for you."},
             %{type: "tool_use", id: "call_123", name: "get_greeting", input: %{"name" => "World"}}
           ]
         }}
      end
    end
  end

  # A mock LLM that returns an error
  defmodule MockLLMError do
    @behaviour Virtuoso.Agent.LLM

    @impl true
    def chat(_messages, _tools, _config) do
      {:error, :api_unavailable}
    end
  end

  defmodule MockTool do
    use Virtuoso.Agent.Tool

    @impl true
    def name, do: "get_greeting"

    @impl true
    def description, do: "Returns a greeting."

    @impl true
    def parameters do
      %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "Name to greet"}
        },
        required: ["name"]
      }
    end

    @impl true
    def execute(%{"name" => name}, _context) do
      {:ok, "Hello, #{name}!"}
    end
  end

  defmodule SimpleAgent do
    use Virtuoso.Agent, llm: Virtuoso.AgentTest.MockLLM

    @impl true
    def system_prompt, do: "You are a test agent."
  end

  defmodule ToolAgent do
    use Virtuoso.Agent, llm: Virtuoso.AgentTest.MockLLMWithTools

    @impl true
    def system_prompt, do: "You are a test agent with tools."

    @impl true
    def tools, do: [Virtuoso.AgentTest.MockTool]
  end

  defmodule ErrorAgent do
    use Virtuoso.Agent, llm: Virtuoso.AgentTest.MockLLMError

    @impl true
    def system_prompt, do: "You are a test agent."
  end

  test "simple agent returns text response" do
    impression = %Impression{
      sender_id: "user_1",
      recipient_id: "bot_1",
      message: "Hi there"
    }

    conversation_state = %{messages: []}

    result = Virtuoso.Agent.respond(SimpleAgent, impression, conversation_state)
    assert result == "Hello from the agent!"
  end

  test "agent with tools executes tool and returns final response" do
    impression = %Impression{
      sender_id: "user_1",
      recipient_id: "bot_1",
      message: "Greet me"
    }

    conversation_state = %{messages: []}

    result = Virtuoso.Agent.respond(ToolAgent, impression, conversation_state)
    assert result == "The greeting is: Hello, World!"
  end

  test "agent handles LLM errors gracefully" do
    impression = %Impression{
      sender_id: "user_1",
      recipient_id: "bot_1",
      message: "Hello"
    }

    conversation_state = %{messages: []}

    result = Virtuoso.Agent.respond(ErrorAgent, impression, conversation_state)
    assert result == "I'm sorry, I encountered an error processing your request."
  end

  test "tool definition includes name, description, and input_schema" do
    defn = MockTool.definition()

    assert defn.name == "get_greeting"
    assert defn.description == "Returns a greeting."
    assert defn.input_schema == MockTool.parameters()
  end
end
