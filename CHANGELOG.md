# Changelog

## 0.1.0 (2026-07-21)

First release of the rebuilt framework — a ground-up rewrite of the 2018
Phoenix chatbot framework as a BEAM-native AI-agent orchestration library.

### Added

- **Ensemble consensus**: parallel LLM member fan-out with `Majority`, `Quorum`,
  and `Judge` strategies, partial-failure tolerance, and per-run telemetry.
  Offline eval harness (`mix virtuoso.eval`) demonstrating the accuracy lift.
- **Conversation processes** over an append-only Postgres event log with
  dedup-key exactly-once semantics; rehydration from the log on start, crash,
  or failover. `Virtuoso.Migrations` for host-app migrations.
- **Thinking pipeline**: FastThinking (deterministic, zero-token matchers) →
  SlowThinking (ensemble routing over a string-keyed routine registry).
- **Bot API**: `use Virtuoso.Bot` with prompt-file system prompts, per-routine
  ensemble overrides, and a plug-in `responder/1`.
- **Generators**: `mix virtuoso.gen.bot`, `mix virtuoso.gen.routine`,
  `mix virtuoso.gen.tool`.
- **LLM layer**: provider behaviour with a Req-based Anthropic adapter
  (completion + SSE streaming), typed errors, and shape-only telemetry.
- **Budget**: daily per-conversation/global token caps, kill switch, defined
  refusal fallback; cluster-wide singleton when the fabric is enabled.
- **Distributed fabric** (optional): Horde-backed registry/supervision with
  libcluster formation; automatic conversation failover, chaos-drill tested.
- **Dashboard example** (`examples/dashboard`): live ensemble runs — votes,
  dissent, latency, cost — from telemetry alone, with a host-provided auth hook.
- `config :virtuoso, :start_repo, false` escape hatch for LLM/Ensemble-only use.
