---
status: pending
priority: p3
issue_id: "010"
tags: [code-review, performance, streaming, llm]
dependencies: []
---

# Streaming buffers the full response — first-token latency unmet, :stream telemetry meaningless

## Problem Statement
`Anthropic.stream/3` does a normal `Req.request` (no `:into`), so the whole SSE
body arrives as one binary; `assemble_stream/3` then splits/parses the entire
string and fires `on_chunk` for all deltas in a burst **after** the full response
has landed. So "streaming" delivers everything at once:
- First-token latency = full-response latency (defeats the point of streaming; the
  LLM moduledoc says "first-token latency matters").
- The `[:virtuoso, :llm, :stream, :stop]` duration is indistinguishable from
  `:complete` — no time-to-first-token signal.

Honestly documented as a v1 limitation in `anthropic.ex`. **This becomes P1 the
moment the web-chat transport (Phase 1) puts streaming in front of a user**, and
the acceptance criterion "streamed first token < 2s" is currently unmet.

## Findings
- `lib/virtuoso/llm/anthropic.ex:~199-234` (`assemble_stream`/`parse_sse_events` on full binary; v1-limitation comment present)
- `lib/virtuoso/llm.ex` (`:stream` telemetry has no first-chunk/TTFT event)
- Flagged P3 by performance, P2 by architecture, and agent-native (missing TTFT event).

## Proposed Solutions
### A. Req :into streaming + line buffer + TTFT telemetry event (recommended before live web-chat)
- Use Req's `:into` callback; maintain an SSE line buffer across chunks (split on `\n`, keep trailing partial); decode `data:` events as they arrive; fire `on_chunk` immediately. Keep the current full-body path as the test/stub fallback.
- Emit `[:virtuoso, :llm, :stream, :first_chunk]` with duration-since-start; document the `:stream, :exception` event too.
- Pros: real incremental streaming + observable TTFT. Cons: SSE chunk-boundary handling. Effort: Medium. Risk: Medium.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `lib/virtuoso/llm/anthropic.ex`, `lib/virtuoso/llm.ex` (telemetry), tests.

## Acceptance Criteria
- [ ] `on_chunk` fires as deltas arrive, not after full-body receipt.
- [ ] A first-chunk/TTFT telemetry event exists and is documented, alongside `:stream, :exception`.
- [ ] Streaming tests exercise incremental delivery (partial SSE chunk across boundaries).

## Work Log
- Created from `/ce:review` of PR #64. Already tracked as a v1 limitation in code + plan.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64
- Plan: "streamed first token < 2s" (non-functional criteria).

## Triage Decision
**DEFERRED** — Honestly documented v1 limitation. Becomes P1 the moment the Phase-1 web-chat *transport* puts streaming in front of a user — fix then, with the TTFT telemetry event, not before.
