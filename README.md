# Virtuoso
"For as the body is one, and hath many members, and all the members of that one body, being many, are one body..."

Virtuoso is a bot orchestration framework built on Phoenix. Simply put, one place for all your bots.

### Quick Start
1. `mix phx.new project_name`
2. `cd project_name`
3. Add `{:virtuoso, ">= 0.0.28"}, {:poison, "~> 3.0"}` to mix.exs
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

### Todo
- Dialogue Flow Client
- Open API
- Admin Portal
