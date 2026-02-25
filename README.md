# Virtuoso
"For as the body is one, and hath many members, and all the members of that one body, being many, are one body..."

Virtuoso is a bot orchestration framework built on Phoenix. Simply put, one place for all your bots.

Virtuoso supports two modes of operation:

- **Classic bots** — Rule-based intent matching (FastThinking) + NLP providers (Wit.ai, Watson) for the SlowThinking pipeline, dispatching to Routines.
- **Modern agents** — LLM-powered agents (Anthropic Claude, OpenAI GPT) with tool use, replacing the entire FastThinking/SlowThinking/Routine pipeline with a single reasoning loop.

### Quick Start (Modern Agent)
1. `mix phx.new project_name`
2. `cd project_name`
3. Add `{:virtuoso, ">= 0.1.0"}, {:jason, "~> 1.0"}` to mix.exs
4. `mix deps.get`
5. `mix virtuoso.gen.agent MyAssistant`
6. Set `ANTHROPIC_API_KEY` in your environment (or configure in `dev.secret.exs`)

Your agent is ready. It comes with an example tool — edit `lib/my_assistant/agent.ex` to customize the system prompt, model, and tools.

### Quick Start (Classic Bot)
1. `mix phx.new project_name`
2. `cd project_name`
3. Add `{:virtuoso, ">= 0.1.0"}, {:poison, "~> 3.0"}` to mix.exs
4. `mix deps.get`
5. `mix virtuoso.gen.bot BotName`
5. `mix virtuoso.gen.client`
6. `mix virtuoso.gen.routine BotName HelloWorld`

Test your webhook.

### Config. If left unconfigured, the project has one default bot - MementoMori. Out of the box, it is a fast thinking bot with a Greeting routine.
dev.exs at the bottom:

```
config :virtuoso, bots: [ BotName ]

import_config "dev.secret.exs"
```

dev.secret.exs:

```
use Mix.Config

config :virtuoso,
  wit_server_access_token: "",
  watson_assistant_version: "",
  watson_assistant_id: "",
  watson_assistant_token: "",
  default_nlp: Wit

config :bot_name,
  fb_page_recipient_id: "",
  fb_page_access_token: "",
  default_routine: BotName.Routine.RoutineName
```

### For Admin testing dashboard add

To setup Admin testing dashboard to your bot application
follow following steps.

1. Setup liveview in your applicaiton by refering to https://hexdocs.pm/phoenix_live_view/installation.html
2.  Add `import VirtuosoWeb.Router` to your _app__web.ex's at router.ex in `def router` function
e.g

```elixir
  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import VirtuosoWeb.Router
    end
  end
```
3.  Add `admin_routes_and_pipelines()` at the top of your `router.ex`
e.g.

```elixir
defmodule YourAppWeb.Router do
  use YourAppWeb, :router

  admin_routes_and_pipelines()
```

4. Also make sure you remove or comment out websocket connect_info in endpoint.ex
e.g.

```elixir
 socket "/live", Phoenix.LiveView.Socket# ,
    # websocket: [connect_info: [session: @session_options]]
```

5. After above steps, you should be able to access dashboard at http://localhost:4000/admin/dashboard

### Supported Platforms
- FbMessenger (needs documentation, rules, and postback accomodations)

### Todo
- Twitter
- Slack
- Twilio
- Gossip

## Executive
Delegates incoming impression to the appropriate Bot.

When an impression is received by a bot, the first thing to do is to identify the intent of the user.

Some platforms make the intent explicit in the structure of the response (such as pressing a button to respond to fb messenger bot) or in structure of the message itself (phone numbers fit into several immediately recognizable patterns).

These types of messages are defined by templates that you set in the FastThinking context of your bot.

Other messages require additional processing for your bot to understand. These get passed into the SlowThinking context. SlowThinking uses NLP libraries to evaluate probable intents and entities.

*YOU MUST TRAIN YOUR NLP PROVIDER TO ACCURATELY GAUGE INTENTS FROM TEXT*

Entities are concepts parsed from your input. All incoming messages have an intent and one or more entities. The question for your bot to answer is: "Which of these entities, if any, are relevant to the satisfaction of the user's intent?"

## Modern Agents

Modern agents replace the FastThinking/SlowThinking/Routine pipeline with a single LLM-driven loop. The agent sends the conversation history to an LLM, which can respond with text or request tool calls. Tool results are fed back into the LLM until it produces a final response.

### Generating an Agent

```bash
# Anthropic Claude (default)
mix virtuoso.gen.agent MyAssistant

# OpenAI GPT
mix virtuoso.gen.agent MyAssistant --llm openai --model gpt-4o
```

This generates:
- `lib/my_assistant.ex` — Bot module
- `lib/my_assistant/agent.ex` — Agent with system prompt and tool config
- `lib/my_assistant/tools/example.ex` — Example tool

### Agent Configuration

```elixir
# config/dev.secret.exs
config :virtuoso,
  anthropic_api_key: "sk-ant-...",
  # or
  openai_api_key: "sk-..."
```

Or set environment variables: `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`.

### Writing Tools

Tools let your agent take actions. Implement the `Virtuoso.Agent.Tool` behaviour:

```elixir
defmodule MyAssistant.Tools.Weather do
  use Virtuoso.Agent.Tool

  @impl true
  def name, do: "get_weather"

  @impl true
  def description, do: "Get current weather for a location."

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        location: %{type: "string", description: "City name"}
      },
      required: ["location"]
    }
  end

  @impl true
  def execute(%{"location" => location}, _context) do
    # Call your weather API here
    {:ok, "72°F and sunny in #{location}"}
  end
end
```

Then register it in your agent:

```elixir
defmodule MyAssistant.Agent do
  use Virtuoso.Agent,
    llm: Virtuoso.Agent.LLM.Anthropic,
    model: "claude-sonnet-4-20250514"

  @impl true
  def system_prompt, do: "You are a weather assistant."

  @impl true
  def tools, do: [MyAssistant.Tools.Weather]
end
```

### Custom LLM Providers

Implement the `Virtuoso.Agent.LLM` behaviour to add support for other providers:

```elixir
defmodule MyApp.LLM.Custom do
  @behaviour Virtuoso.Agent.LLM

  @impl true
  def chat(messages, tools, config) do
    # Call your LLM API and return:
    # {:ok, %{type: :text, content: "response"}}
    # or
    # {:ok, %{type: :tool_use, tool_calls: [...], content: [...]}}
  end
end
```

### Todo
- Streaming responses
- Admin Portal agent testing
- Multi-agent orchestration
