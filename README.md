# Virtuoso

Virtuoso is a bot orchestration framework built on Phoenix. Simply put, one place for all your bots.

## Medium
Medium is our platform library. She is responsible for receiving messages from *any* platform and translating them into a universally understood language.

### Supported Platforms
- FbMessenger (needs documentation, rules, and postback accomodations)

### Todo
- Slack
- Twitter
- Twilio

## Executive
Delegates incoming impression to the appropriate Bot.

## Cognition
Think of Cognition as a nested router for your bot.

When an impression is received by a bot, the first thing to do is to identify the intent of the user.

Some platforms make the intent explicit in the structure of the response (such as pressing a button to respond to fb messenger bot) or in structure of the message itself (phone numbers fit into several immediately recognizable patterns).

These types of messages are defined by templates that you set in the FastThinking context of your bot.

Other messages require additional processing for your bot to understand. These get passed into the SlowThinking context. SlowThinking uses NLP libraries to evaluate probable intents and entities.

*YOU MUST TRAIN YOUR NLP PROVIDER TO ACCURATELY GAUGE INTENTS FROM TEXT*

Entities are concepts parsed from your input. All incoming messages have an intent and one or more entities. The question for your bot to answer is: "Which of these entities, if any, are relevant to the satisfaction of the user's intent?"

### Todo
- Wit NLP Client
- Dialogue Flow Client

## Homunculus
Generates Bots and Routines. Named for the little men in our head.

### Todo
- New Bot Generator
- New Routine Generator
- Open API
- Admin Portal
