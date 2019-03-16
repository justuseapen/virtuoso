# Virtuoso
"For as the body is one, and hath many members, and all the members of that one body, being many, are one body..."

Virtuoso is a bot orchestration framework built on Phoenix. Simply put, one place for all your bots.

### Quick Start
1. `mix phx.new project_name`
2. `cd project_name`
3. Add `{:virtuoso, ">= 0.0.24"}` to mix.exs
4. `mix deps.get`
5. `mix virtuoso.gen.bot BotName`
5. `mix virtuoso.gen.client`
6. `mix virtuoso.gen.routine BotName HelloWorld`
7. Add webhook to router and skip csrf:

```
  pipeline :unprotected_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_secure_browser_headers
  end

  scope "/", ProjectNameWeb do
    pipe_through :unprotected_browser
    get "/webhook", WebhookController, :verify
    post "/webhook", WebhookController, :create
  end
```

Test your webhook.

### Config
dev.exs at the bottom:
`config :virtuoso, bots: [ BotName ]
`import_config "dev.secret.exs"`

dev.secret.exs:
```
config :virtuoso,
  wit_server_access_token: "KGNCS5UWL7Y33B..."

config :project_name,
  fb_page_recipient_ids: [100002891787948, 100002891787123],
  fb_page_access_token: "EAAEywOmMYuIBAFI7IN..."
```

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
