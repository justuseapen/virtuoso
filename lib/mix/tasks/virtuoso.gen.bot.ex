defmodule Mix.Tasks.Virtuoso.Gen.Bot do
  @shortdoc "Generates a Virtuoso bot: bot module, fast-thinker, starter routine, prompt file"

  @moduledoc """
  Generates a complete, working bot under your app's `lib/` and `priv/`:

      mix virtuoso.gen.bot Demo

  creates

    * `lib/demo/bot.ex` — `Demo.Bot`, wired with `use Virtuoso.Bot`
    * `lib/demo/fast/greeting.ex` — a zero-token FastThinking matcher
      (the bot chats immediately, no API key required)
    * `lib/demo/routines/echo.ex` — a starter routine reached via ensemble routing
    * `priv/prompts/demo/router.md` — the routing system prompt as a **file**,
      embedded at compile time (`@external_resource` recompiles on edit)

  The namespace may be nested (`mix virtuoso.gen.bot MyApp.Support`).

  Try it in IEx:

      imp = Virtuoso.Impression.new(
        channel: :console, conversation_id: "c1", sender_id: "u1",
        message_id: "m1", text: "hi"
      )
      Demo.Bot.responder().(imp, %{})
      #=> {:reply, "Hello! I'm Demo — ..."}
  """

  use Mix.Task

  import Mix.Generator

  alias Mix.Virtuoso, as: Gen

  @impl true
  def run(argv) do
    case argv do
      [name | _] ->
        {module, path} = Gen.module_arg!(name, "bot namespace")
        generate(module, path)

      [] ->
        Mix.raise("Expected a bot namespace, e.g.: mix virtuoso.gen.bot Demo")
    end
  end

  defp generate(module, path) do
    assigns = [module: module, path: path]

    create_file(Path.join(["lib", path, "bot.ex"]), bot_template(assigns))
    create_file(Path.join(["lib", path, "fast", "greeting.ex"]), greeting_template(assigns))
    create_file(Path.join(["lib", path, "routines", "echo.ex"]), echo_template(assigns))
    create_file(Path.join(["priv", "prompts", path, "router.md"]), prompt_template(assigns))

    Mix.shell().info("""

    #{module}.Bot is ready. Wire it into a conversation:

        Virtuoso.Conversation.deliver(impression, responder: #{module}.Bot.responder())

    The greeting fast-thinker replies without an API key; ensemble routing to
    routines needs ANTHROPIC_API_KEY (or an injected :llm adapter in tests).
    Add routines with: mix virtuoso.gen.routine #{module} MyRoutine
    """)
  end

  embed_template(:bot, """
  defmodule <%= @module %>.Bot do
    @moduledoc \"\"\"
    A Virtuoso bot: FastThinking matchers first (zero tokens), then ensemble
    routing over the routine registry, then the winning routine replies.
    \"\"\"

    use Virtuoso.Bot

    # The routing prompt lives in a file, embedded at compile time.
    # @external_resource recompiles this module when the file changes.
    @router_prompt_path "priv/prompts/<%= @path %>/router.md"
    @external_resource @router_prompt_path
    @router_prompt File.read!(@router_prompt_path)

    @impl true
    def system, do: @router_prompt

    @impl true
    def fast, do: [<%= @module %>.Fast.Greeting]

    @impl true
    def routines do
      %{
        "echo" => <%= @module %>.Routines.Echo
      }
    end

    # Ensemble defaults for routing; override per routine with
    # {module, ensemble: [n: 5, strategy: :judge]}.
    @impl true
    def ensemble, do: [n: 3, strategy: :majority]
  end
  """)

  embed_template(:greeting, """
  defmodule <%= @module %>.Fast.Greeting do
    @moduledoc \"\"\"
    A FastThinking matcher: answers greetings deterministically, spending zero
    tokens. Anything else falls through to ensemble routing.
    \"\"\"

    @behaviour Virtuoso.Thinking.Fast

    alias Virtuoso.Impression

    @greetings ~w(hi hello hey howdy yo)

    @impl true
    def match(%Impression{text: text}, _context) when is_binary(text) do
      if String.downcase(String.trim(text)) in @greetings do
        {:match, {:reply, "Hello! I'm <%= @module %> — ask me anything."}}
      else
        :no_match
      end
    end

    def match(_impression, _context), do: :no_match
  end
  """)

  embed_template(:echo, """
  defmodule <%= @module %>.Routines.Echo do
    @moduledoc \"\"\"
    A starter routine. The ensemble votes on the route; the winning routine runs
    exactly once (side effects happen post-consensus, never per member).
    \"\"\"

    @behaviour Virtuoso.Routine

    alias Virtuoso.Impression

    @impl true
    def run(%Impression{text: text}, _context) do
      {:reply, "You said: \#{text}"}
    end
  end
  """)

  embed_template(:prompt, """
  You are the router for <%= @module %>, a helpful assistant.

  Read the user's message and choose the single intent that best handles it.
  Prefer a specific intent over a general one when both could apply.

  <!-- The framework appends the valid intent list and reply format after this
       preamble, so you never need to list routine names here. -->
  """)
end
