# Virtuoso
"For as the body is one, and hath many members, and all the members of that one body, being many, are one body..."

Virtuoso is a bot orchestration framework built on Phoenix. Simply put, one place for all your bots.

### Quick Start
1. `mix phx.new project_name`
2. `cd project_name`
3. Add `{:virtuoso, ">= 0.0.24"}`
4. `mix deps.get`
5. `mix virtuoso.gen.bot BotName`
5. `mix virtuoso.gen.client BotName FbMessenger`
6. `mix virtuoso.gen.routine BotName HelloWorld`
7. Add webhook to router

```
get "/webhook", WebhookController, :verify
post "/webhook", WebhookController, :create
```

Test your webhook.

8. Add your page access token to your config

### Supported Platforms
- FbMessenger (needs documentation, rules, and postback accomodations)

### Todo
- Slack
- Twitter
- Twilio

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
