# Virtuoso

Virtuoso is a bot orchestration framework built on Phoenix. Simply put, one place for all your bots.

## ToDo
- [ ] `mix virtuoso.gen.client` to add an integration
  - Add config for page (page_access_token)

### Demo Prep
Demo should consist of the following:
1. `mix phx.new $PROJECT_NAME`
2. Add `{:virtuoso, "~> x.x.x"}` to `mix.exs`
3. `mix deps.get`
4. `mix virtuoso.gen.bot $BOT_NAME`
5. `mix virtuoso.gen.client fb_messenger`
6. Facebook app and page configuration
7. ngrok the webhook and boom working bot

#### FbMessenger Setup
1. Create an app (and a test app)
2. Setup Messenger (Get page access token)
3. Create a page (you need a page access token)
4.

## Medium
Medium is our platform library. She is responsible for receiving messages from *any* platform and translating them into a universally understood language.

## Bot
A Bot consists of three parts
- FastThinking: Identifies user intent from impression structure
- SlowThinking: Attempts to id intent from NLP analysis
- Routines: Executes a routine based on user intent


