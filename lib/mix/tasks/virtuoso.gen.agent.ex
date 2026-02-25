defmodule Mix.Tasks.Virtuoso.Gen.Agent do
  @moduledoc """
  Generates a modern LLM-powered agent bot.

      mix virtuoso.gen.agent MyAssistant

  This creates an agent-style bot that uses an LLM (like Claude) instead of
  the traditional FastThinking/SlowThinking/Routine pipeline.

  Generated files:

    * `lib/my_assistant.ex` — Bot module that delegates to the agent
    * `lib/my_assistant/agent.ex` — Agent module with system prompt and tool config
    * `lib/my_assistant/tools/` — Directory for tool modules
    * `lib/my_assistant/tools/example.ex` — Example tool implementation

  ## Options

    * `--llm` - LLM provider (`anthropic` or `openai`, default: `anthropic`)
    * `--model` - Model name (default: `claude-sonnet-4-20250514` for Anthropic, `gpt-4o` for OpenAI)
  """
  use Mix.Task
  alias Virtuoso.Bot
  alias Virtuoso.Utilities.Util

  def run(args) do
    {opts, [bot_module_name | _], _} =
      OptionParser.parse(args, strict: [llm: :string, model: :string])

    llm = Keyword.get(opts, :llm, "anthropic")
    model = Keyword.get(opts, :model, default_model(llm))

    bot_module_name
    |> generate_directories()
    |> generate_bot_interface(llm, model)
    |> generate_agent_module(llm, model)
    |> generate_example_tool()
    |> generate_bot_entries()
  end

  defp default_model("anthropic"), do: "claude-sonnet-4-20250514"
  defp default_model("openai"), do: "gpt-4o"
  defp default_model(_), do: "claude-sonnet-4-20250514"

  defp generate_directories(bot_module_name) do
    bot_dir = Bot.bot_directory_path(bot_module_name)
    tools_dir = bot_dir <> "tools"

    Mix.Generator.create_directory(bot_dir)
    Mix.Generator.create_directory(tools_dir)

    bot_module_name
  end

  defp generate_bot_interface(bot_module_name, llm, _model) do
    file_path =
      bot_module_name
      |> Macro.underscore()
      |> String.replace_prefix("", "#{File.cwd!()}/lib/")
      |> String.replace_suffix("", ".ex")

    Mix.Generator.create_file(file_path, bot_template(bot_module_name))

    bot_module_name
  end

  defp generate_agent_module(bot_module_name, llm, model) do
    file_path =
      bot_module_name
      |> Bot.bot_directory_path()
      |> String.replace_suffix("", "agent.ex")

    provider = provider_module(llm)
    Mix.Generator.create_file(file_path, agent_template(bot_module_name, provider, model))

    bot_module_name
  end

  defp generate_example_tool(bot_module_name) do
    file_path =
      bot_module_name
      |> Bot.bot_directory_path()
      |> String.replace_suffix("", "tools/example.ex")

    Mix.Generator.create_file(file_path, tool_template(bot_module_name))

    bot_module_name
  end

  defp generate_bot_entries(bot_module_name) do
    with {:ok, content} <- Util.get_current_state(),
         {:ok, decoded_contents} <- Poison.decode(content),
         new_content =
           Util.atomic_map(decoded_contents)
           |> Map.put(bot_module_name, ["active", "agent"]),
         {:ok, encoded_new_content} <- Poison.encode(new_content),
         true <- Mix.Generator.create_file("bot.lock", encoded_new_content, force: true) do
      bot_module_name
    else
      {:error, reason} ->
        Mix.shell().info("Note: Could not update bot.lock: #{inspect(reason)}")
        bot_module_name
    end
  end

  defp provider_module("openai"), do: "Virtuoso.Agent.LLM.OpenAI"
  defp provider_module(_), do: "Virtuoso.Agent.LLM.Anthropic"

  defp bot_template(bot_module_name) do
    """
    defmodule #{bot_module_name} do
      @moduledoc \"""
      #{bot_module_name} — an LLM-powered agent bot.
      \"""

      @recipient_ids [
        Application.get_env(:#{Macro.underscore(bot_module_name)}, :fb_page_recipient_id)
      ]

      @tokens %{
        fb_page_access_token:
          Application.get_env(:#{Macro.underscore(bot_module_name)}, :fb_page_access_token)
      }

      def recipient_ids, do: @recipient_ids

      def token(:fb), do: @tokens[:fb_page_access_token]

      @doc \"""
      Delegates to the agent for LLM-powered responses.
      \"""
      def respond_to(impression, conversation_state) do
        Virtuoso.Agent.respond(#{bot_module_name}.Agent, impression, conversation_state)
      end
    end
    """
  end

  defp agent_template(bot_module_name, provider, model) do
    """
    defmodule #{bot_module_name}.Agent do
      @moduledoc \"""
      Agent configuration for #{bot_module_name}.

      Customize the system prompt, tools, and LLM settings here.
      \"""

      use Virtuoso.Agent,
        llm: #{provider},
        model: "#{model}"

      @impl true
      def system_prompt do
        \"""
        You are #{bot_module_name}, a helpful assistant.

        Be concise and friendly in your responses.
        \"""
      end

      @impl true
      def tools do
        [
          #{bot_module_name}.Tools.Example
        ]
      end
    end
    """
  end

  defp tool_template(bot_module_name) do
    """
    defmodule #{bot_module_name}.Tools.Example do
      @moduledoc \"""
      An example tool. Replace this with your own tools.
      \"""

      use Virtuoso.Agent.Tool

      @impl true
      def name, do: "get_greeting"

      @impl true
      def description, do: "Returns a greeting for the given name."

      @impl true
      def parameters do
        %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "The name to greet"}
          },
          required: ["name"]
        }
      end

      @impl true
      def execute(%{"name" => name}, _context) do
        {:ok, "Hello, \#{name}! Welcome."}
      end
    end
    """
  end
end
