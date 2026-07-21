# Virtuoso

> "For as the body is one, and hath many members, and all the members of that one body, being many, are one body..."

Virtuoso is a **BEAM-native AI-agent orchestration framework**: the actor model
applied to LLM agents.

- **Parallel consensus (ensembles).** N lightweight processes query LLMs
  concurrently; their *structured* outputs are aggregated by vote (majority,
  quorum, or an LLM judge). Independently-noisy members cancel each other's
  errors — in the bundled offline eval, majority-of-5 lifts accuracy from
  **59.7% → 88.9%** at a 35% per-member error rate (`mix virtuoso.eval`).
- **Distributed compute fabric.** Conversations and singletons run on a
  [Horde](https://hex.pm/packages/horde)-backed cluster: a node dies, its
  processes restart on survivors in tens of milliseconds and rehydrate from the
  event log. Correctness never rests on the registry — it rests on the log.
- **Exactly-once on at-least-once delivery.** An append-only Postgres event log
  with a unique dedup key is the source of truth: duplicate webhooks collapse to
  one event, replies to replayed messages are served from the log, and a crashed
  conversation loses at most the in-flight message.

Consensus is on **decisions, not text**: the ensemble votes on categorical
outputs (routes, classifications, extractions), then the winning routine
generates the reply or performs the side effect **once**. N members never mean
N replies or N side effects.

## Five-minute bot

```sh
mix virtuoso.gen.bot Demo
```

That scaffolds a complete bot — a FastThinking greeting matcher (deterministic,
zero tokens), a starter routine reached by ensemble routing, and the routing
system prompt as a **file** (`priv/prompts/demo/router.md`, embedded at compile
time):

```elixir
imp = Virtuoso.Impression.new(
  channel: :console, conversation_id: "c1", sender_id: "u1",
  message_id: "m1", text: "hi"
)

Demo.Bot.responder().(imp, %{})
#=> {:reply, "Hello! I'm Demo — ask me anything."}   # no API key needed
```

With `ANTHROPIC_API_KEY` set, non-greeting messages route through the ensemble
to your routines. Add more with `mix virtuoso.gen.routine Demo Booking` and
`mix virtuoso.gen.tool Demo Weather` (a *tool* is a routine whose job is a side
effect, guaranteed post-consensus).

## Installation

```elixir
def deps do
  [{:virtuoso, "~> 0.1"}]
end
```

Create the event log from your app's migration (the Oban pattern):

```elixir
defmodule MyApp.Repo.Migrations.AddVirtuoso do
  use Ecto.Migration

  def up, do: Virtuoso.Migrations.up()
  def down, do: Virtuoso.Migrations.down()
end
```

Point Virtuoso's repo at your Postgres:

```elixir
config :virtuoso, Virtuoso.Repo, url: System.get_env("DATABASE_URL")
```

Only using the LLM/Ensemble layers (no conversations)? Skip Postgres entirely:

```elixir
config :virtuoso, :start_repo, false
```

## Architecture

```
channel → Impression v1 → conversation process → thinking pipeline → reply
             (translate)      (FIFO, rehydrates     Fast (0 tokens)
                               from event log)      → Slow (ensemble routes,
                    │                                  routine replies once)
              event log ◀── append inbound/outbound (dedup) ──▶ event log
                    │
              every LLM call passes the Budget gate and emits telemetry
```

| Module | Role |
|---|---|
| `Virtuoso.Bot` | `use Virtuoso.Bot` — declare fast-thinkers, routines, ensemble defaults, and the prompt file; get a plug-in `responder/1` |
| `Virtuoso.Ensemble` | parallel member fan-out + consensus strategies (`Majority`, `Quorum`, `Judge`) with partial-failure tolerance |
| `Virtuoso.Conversation` | one process per conversation; serial mailbox = FIFO; rehydrates from the log on start/failover |
| `Virtuoso.Conversation.Log` | append-only Postgres event log; unique dedup index = exactly-once |
| `Virtuoso.LLM` | provider behaviour (`complete/2`, `stream/3`); Req-based Anthropic adapter with typed errors; offline mock for tests |
| `Virtuoso.Budget` | daily token caps (per-conversation + global) with kill switch and a defined refusal fallback; cluster-wide singleton on the fabric |
| `Virtuoso.Fabric` | seam between single-node (Registry/DynamicSupervisor) and clustered (Horde) process placement |
| `Virtuoso.Channel` | channel adapter behaviour + HMAC-SHA256 webhook verification |

The library core is **Phoenix-free**. The live telemetry dashboard (votes,
dissent, latency, cost per decision) is a host app in `examples/dashboard`.

## Clustering (optional)

```elixir
config :virtuoso, Virtuoso.Fabric, enabled: true
config :virtuoso, Virtuoso.Fabric, topologies: [
  fly: [strategy: Cluster.Strategy.DNSPoll, config: [query: "myapp.internal", ...]]
]
```

With the fabric on, conversations distribute across nodes and fail over
automatically (measured 52–307ms in the chaos drills, target was 5s). See
`docs/operations/rolling-deploys.md` for deploy invariants and
`docs/spikes/2026-07-20-horde-spike-report.md` for the drill findings.

## Telemetry (stable, versioned from 0.1.0)

- `[:virtuoso, :llm, :complete | :stream, :start | :stop | :exception]` —
  durations, model, outcome, token usage. **Shape-only: never transcripts**
  (enforced by test — safe to ship to any metrics backend).
- `[:virtuoso, :ensemble, :run, :start | :stop]` — outcome, decision (a
  categorical label, not user text), vote count, members ok/dropped, usage.

## Budget

```elixir
config :virtuoso, Virtuoso.Budget,
  per_conversation_daily: 50_000,
  global_daily: 1_000_000
```

Caps are genuinely daily (they reset at UTC rollover), the kill switch refuses
everything immediately, and an over-budget turn gets a defined refusal message
instead of spending. The N-members multiplier is structural, so the gate is not
optional.

## Development

Requires Elixir **1.15.6-otp-26** (pinned in `.tool-versions`) and local
Postgres.

```sh
mix deps.get
mix ecto.setup
mix test                        # fully offline (mock LLM); needs Postgres
mix test --include distributed  # multi-node chaos drills
mix virtuoso.eval               # the consensus accuracy proof
```

## License

MIT — see [LICENSE](https://github.com/justuseapen/virtuoso/blob/master/LICENSE).
