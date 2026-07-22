# Chat Showcase — design

**Status:** approved (brainstormed 2026-07-22)
**Goal:** a deployed, public, ChatGPT-like chat demo for Virtuoso where the
ensemble engine is *visible* — every message chats with a real LLM while a live
panel shows the consensus machinery (route, votes, dissent, latency, cost,
budget) that produced the reply.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Audience | Deployed public showcase (Fly.io), linked from README/Hex |
| LLM | Real Anthropic key, protected by `Virtuoso.Budget` tight caps |
| Angle | Chat + "under the hood" engine panel (not a plain clone) |
| Streaming | Whole replies; the engine panel animating live *is* the "thinking" UX. UI leaves room for token streaming later (todo 010) |
| Structure | Approach A — evolve `examples/dashboard` into the showcase app (chat at `/`, ops dashboard at `/dashboard`) |

## Architecture

One Phoenix host app (`examples/dashboard`, OTP app `:virtuoso_dashboard`) —
the library core stays Phoenix-free. Reused: endpoint, telemetry Collector
(ring buffer → PubSub), layouts, deps-served LiveView JS.

New in the example app:

| Module | Purpose |
|---|---|
| `VirtuosoDashboard.Bot` | `use Virtuoso.Bot`; prompt-file router persona; ensemble defaults `n: 3, strategy: :majority` |
| `VirtuosoDashboard.Bot.Fast.Greeting` | zero-token greeting matcher — demos the fast path in the panel |
| `VirtuosoDashboard.Bot.Routines.Answer` | free-form generation: single Claude call with bounded history, post-consensus, wrapped in `Budget.with_budget` |
| `VirtuosoDashboard.Bot.Routines.AboutVirtuoso` | same generation shape, prompt-file persona that explains the framework |
| `VirtuosoDashboardWeb.ChatLive` | chat UI + engine panel at `/` |

Routing stays honest: two genuinely different routes ("answer" vs
"about_virtuoso") so consensus has a real decision to make; the greeting
fast-thinker shows the 0-token path.

### Framework change (the only one)

`Virtuoso.Ensemble.run/2` gains an optional `:telemetry_meta` map, merged into
`[:virtuoso, :ensemble, :run, :start|:stop]` metadata. Additive, documented as
part of the telemetry contract. `Virtuoso.Thinking.Slow` passes
`%{conversation_id: imp.conversation_id}` so the panel can filter events to the
viewer's own conversation. LLM-level events stay shape-only (no change).

## Chat flow

1. First visit mints a random `conversation_id`, stored in the session cookie
   (per browser, survives refresh).
2. Send → `ChatLive` builds `Virtuoso.Impression` (channel `:web`, UUID
   `message_id`, text capped at 500 chars) → async task runs
   `Conversation.deliver(imp, responder: Bot.responder())` — the real pipeline:
   event-log append, dedup, FastThinking, ensemble routing, generation.
3. While in flight: input disabled, panel animates from telemetry (LLM calls
   completing, then the run card).
4. Reply arrives whole and appends to the transcript. History for generation is
   the conversation's bounded history (`@history_limit`), passed via responder
   context.

## Engine panel

Subscribes to the Collector's PubSub; renders only events whose
`conversation_id` matches the session (LLM events without one feed the global
dashboard only).

- **Run card** (latest + a few prior): route decision, votes `k/n`, dissent,
  outcome (consensus/fallback), latency, token usage. Fast-path replies render
  a distinct "fast path — 0 tokens" card.
- **Budget bars**: your conversation (`Budget.spent/2` vs per-conversation
  cap) and global (`global_spent/1` vs global cap), polled on each run + timer.
- Copy in the panel briefly explains what the viewer is seeing (one line per
  element, links to GitHub/Hex).

## Spend & abuse protection

The framework's own Budget is the enforcement layer (that's the demo):

- per-conversation daily cap (small, e.g. 10k tokens) — one visitor can't hog
- global daily cap (hard ceiling = max daily spend) — set via env
- kill switch reachable via IEx/env for emergencies
- Budget refusal renders as a normal bot reply (the framework's refusal
  message) with the panel showing the cap hit — graceful, on-message failure
- Input length cap; empty messages ignored. No accounts, no stored PII beyond
  the event log's transcript (documented in the app README; PII policy as per
  dashboard README).

## Deployment (Fly.io)

- `Dockerfile` + `fly.toml` in `examples/dashboard`; Fly Postgres attached;
  release runs `Virtuoso.Migrations` via a release task.
- Secrets: `ANTHROPIC_API_KEY`, `SECRET_KEY_BASE`, dashboard basic-auth creds.
- Env-tunable: budget caps, model, port. `check_origin` locked to the Fly
  domain (replaces the dev-only `check_origin: false`).
- `/dashboard` behind the existing host-auth hook (basic auth from env);
  `/` public.

## Error handling

| Failure | Behavior |
|---|---|
| Budget exceeded / kill switch | Framework refusal message as bot reply; panel shows cap |
| LLM typed error (429/529/timeout) | Friendly fallback reply; run card shows dropped members / error outcome |
| All members fail | SlowThinking fallback reply (existing behavior) |
| Task crash | LiveView traps exit → "something went wrong" reply; conversation process unaffected |

## Testing

- Ensemble `:telemetry_meta` passthrough unit test (start + stop metadata).
- Bot/routine tests with injected `:llm` (no network).
- LiveView test: mount `/`, send a message against a stub LLM, assert the
  reply renders and a run card appears.
- Full existing suite (`mix test`, credo, dialyzer, format) stays green;
  example app compiles with `--warnings-as-errors`.

## Out of scope (v1)

- Token streaming (todo 010) — UI designed so it can slot in later.
- Accounts/auth for chat visitors. (Transcript *does* survive refresh: on
  mount, `ChatLive` rebuilds it from `Log.recent_events_for/2` for the
  session's conversation — the event log demoing itself.)
- Multi-node Fly deployment (fabric on) — a natural v2 flex, not required to
  ship.
