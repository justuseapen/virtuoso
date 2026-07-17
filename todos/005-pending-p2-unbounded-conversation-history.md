---
status: pending
priority: p2
issue_id: "005"
tags: [code-review, performance, memory, otp]
dependencies: []
---

# Conversation holds unbounded history — O(n) rehydration, O(n²) appends, no truncation

## Problem Statement
`Conversation.init/1` rehydrates by loading the **entire** event log for the
conversation (`Log.events_for/1` = unbounded `Repo.all`) into an in-memory
`history` list held in GenServer state for the process lifetime. Each turn grows
it with `history ++ [entry]` (O(current length) append → O(N²) over N turns), and
the responder receives the full history every call. The "history truncation
policy" the plan references is a stub — nothing bounds the list.

Impact for long-lived conversations:
- Memory: ~5 MB/process at 5k×1KB events → ~50 GB across 10k active conversations.
- Rehydration: full table read + decode blocks `init/1`, paid again on every cold
  start AND on the `:noproc` retry path.
- O(N²) history appends add measurable per-turn latency that eats the p95 < 8s budget.

## Findings
- `lib/virtuoso/conversation.ex:~125-133` (init rehydrates full log into state)
- `lib/virtuoso/conversation.ex:~150,155` (`history ++ [entry]` per turn)
- `lib/virtuoso/conversation/log.ex:~92-99` (`events_for/1` unbounded `Repo.all`)
- Flagged P1 by performance-oracle; architecture concurs (Phase-3 handoff multiplies replay cost).

## Proposed Solutions
### A. Bounded replay + O(1) append (recommended)
1. Add `recent_events_for/2` (`order_by: [desc: id], limit: n`, reverse in memory) — load only the last N (e.g. 200–500; the LLM context window caps useful history anyway).
2. Keep `history` newest-first with `[entry | history]` (O(1)) and reverse when handed to the responder, or cap to N dropping from the front.
- Pros: bounded memory + fast rehydration; pairs with the composite index (todo 008).
- Cons: full history for audit must come from the log table, not process state (correct anyway).
- Effort: Medium. Risk: Low.

### B. Cap in-state list only, keep full-log replay
Simpler but still pays the full `Repo.all` on rehydrate.
- Pros: smaller change. Cons: doesn't fix rehydration cost. Effort: Small. Risk: Low.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `lib/virtuoso/conversation.ex`, `lib/virtuoso/conversation/log.ex`.
- Coordinate with todo 008 (composite `(conversation_id, id)` index) so the bounded read is a pure ordered range scan.

## Acceptance Criteria
- [ ] Rehydration loads at most N events, ordered correctly.
- [ ] Per-turn history append is not O(current length).
- [ ] Test: a conversation with > N events rehydrates with a bounded history.

## Work Log
- Created from `/ce:review` of PR #64.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64
- Plan: "history truncation/summarization policy for context window" (Phase 1, currently a stub).

## Triage Decision
**DEFERRED** — Real, but Medium effort touching rehydration + history representation. Not a Phase-1 *scope* blocker (no long-lived conversations in a not-yet-deployed framework). Do alongside the SlowThinking context-window work, before any real deployment. Pairs with 008.
