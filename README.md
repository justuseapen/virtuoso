# Virtuoso

> "For as the body is one, and hath many members, and all the members of that one body, being many, are one body..."

Virtuoso is a **BEAM-native AI-agent orchestration framework**. It runs many
lightweight processes to reason with LLMs concurrently, aggregates their
structured outputs by consensus, and (in later phases) spreads conversations
across a self-healing cluster — the actor model applied to agent orchestration.

It is a rebuild of the original 2018 Phoenix chatbot framework: the cognitive
shape is kept (a deterministic fast path ahead of an LLM reasoning step), but the
pre-LLM NLP guts (Wit.ai / Watson intent classification) are replaced with LLM
ensembles behind a clean behaviour.

> **Status:** Phase 1 — a useful modern single-node framework. The ensemble
> (parallel consensus) and fabric (distributed compute) layers are the eventual
> flagship features; see `docs/plans/` for the roadmap.

## Architecture (Phase 1)

```
channel → Impression v1 → conversation process → responder → reply
             (translate)      (FIFO, rehydrates      (thinking
                               from event log)        pipeline)
                    │                                     │
              event log ◀────── append inbound/outbound (dedup) ──────▶ event log
                    │                                     │
              every LLM call passes the Budget gate and emits telemetry
```

- **`Virtuoso.Impression`** — the channel-neutral, versioned message envelope
  every channel translates to and from. `dedup_key/1` (`"<channel>:<id>"`) is the
  event log's idempotency key.
- **`Virtuoso.Conversation`** — one GenServer per conversation, addressed by a
  Registry and started on demand. FIFO ordering per conversation falls out of the
  serial mailbox; state is rehydrated from the event log on start, so a crash
  loses at most the in-flight message.
- **`Virtuoso.Conversation.Log`** — append-only Postgres event log, the source of
  truth. A unique index on the dedup key gives exactly-once processing (a
  duplicate webhook yields one event); recording outbound send-intent *before* the
  channel send prevents double-sends.
- **`Virtuoso.LLM`** — the behaviour every provider implements (`complete/2`,
  `stream/3`), with a Req-based Anthropic adapter and typed `Virtuoso.LLM.Error`s
  (429 → `:rate_limited`, 529 → `:overloaded`, timeout, …). Tests run fully
  offline against `Virtuoso.LLM.Mock`.
- **`Virtuoso.Budget`** — cluster-global token caps (per-conversation + global
  daily) with a kill switch and a defined refusal fallback. Every LLM call is
  gated.
- **`Virtuoso.Routine`** — explicit string-keyed routine registry (replaces the
  legacy `String.to_atom` dispatch and its atom-exhaustion DoS).
- **`Virtuoso.Channel`** — the behaviour a channel adapter implements
  (`translate_in/1`, `send_out/2`, `verify_webhook/2`). Web chat is first-class;
  `Virtuoso.Channel.Signature` provides reusable HMAC-SHA256 webhook verification.

The library core is **Phoenix-free**. Channel transports (Phoenix Channels /
LiveView) and the telemetry dashboard live in an optional host application.

## Public API & extension points

Implement these behaviours to extend the framework:

| Behaviour | Implement to… |
|---|---|
| `Virtuoso.LLM` | add an LLM provider |
| `Virtuoso.Channel` | add a messaging channel |
| `Virtuoso.Routine` | add a routine/tool |

### Telemetry (stable, versioned from 0.1.0)

Every LLM call through `Virtuoso.LLM.complete/2` and `stream/3` emits:

- `[:virtuoso, :llm, :complete | :stream, :start]` — `%{system_time}`;
  metadata `%{model, request}`
- `[:virtuoso, :llm, :complete | :stream, :stop]` — `%{duration}`;
  metadata `%{model, outcome, usage, error_reason}`
- `[:virtuoso, :llm, :complete | :stream, :exception]` — on a raised bug;
  re-raised after the event

## Getting started (development)

Requires Elixir **1.15.6-otp-26** (pinned in `.tool-versions`) and a local
Postgres.

```sh
mix deps.get
mix ecto.setup      # create + migrate the dev database
mix test            # full suite — offline (no live LLM); needs local Postgres
```

Configure the Anthropic API key (the default adapter reads it from the
environment):

```sh
export ANTHROPIC_API_KEY="sk-ant-..."
```

Caps and adapter are configurable:

```elixir
# config/config.exs
config :virtuoso, :llm, Virtuoso.LLM.Anthropic
config :virtuoso, Virtuoso.Budget, per_conversation_daily: 50_000, global_daily: 1_000_000
```

## Testing

`mix test` is fully offline — the LLM behaviour is served by an in-process mock,
so no request ever hits the network. It does require a local Postgres (the event
log is the persistence layer); "offline" means no live LLM, not no database.

## License

MIT
