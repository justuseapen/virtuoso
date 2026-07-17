---
status: complete
priority: p2
issue_id: "004"
tags: [code-review, correctness, exactly-once, budget]
dependencies: []
---

# Duplicate inbound re-runs the responder → divergent reply + double LLM spend

## Problem Statement
In `Conversation.handle_call/3`, `Log.append_inbound/1` correctly dedups (returns
`:duplicate` on a replayed webhook) and `maybe_append_history` skips the history
append. **But the responder still runs unconditionally afterward**, and
`commit_reply` still calls `append_outbound`.

Two consequences on a duplicate (webhook retry):
1. The responder — a real, paid LLM call in Phase 2 — executes *again* and can
   produce a *different* reply than the one originally persisted/sent. The caller
   receives a reply that was never the one stored (`append_outbound` idempotently
   returns the original, but its status/result is discarded via `_status`).
2. It re-spends tokens per retry. This defeats the plan's acceptance criterion
   "replaying a duplicate webhook yields exactly one reply and one billing event"
   and creates a retry-storm amplification vector.

The DB stays consistent (outbound dedup key prevents a duplicate row / double
send), so this is not a double-send — it's a wasted/divergent recomputation.

## Findings
- `lib/virtuoso/conversation.ex:~136-147` — `responder.(imp, state.history)` runs
  regardless of `status`; only history-append branches on `:duplicate`.
- `lib/virtuoso/conversation.ex:~150-155` — `commit_reply` re-runs `append_outbound`.
- Converged: architecture (P2), security (P3), agent-native (implied). Confirmed against source.

## Proposed Solutions
### A. Short-circuit on :duplicate inbound (recommended)
When `append_inbound` returns `:duplicate`, look up the previously-logged outbound
reply (by `"#{message_id}:reply"`) and return it without invoking the responder.
- Pros: exactly-one billing + identical reply on replay; closes the amplification vector.
- Cons: one extra lookup on the duplicate path (rare).
- Effort: Small. Risk: Low.

### B. Gate the responder on status, return :noreply on duplicate
Simpler but changes replay semantics (caller gets `:noreply` instead of the reply).
- Pros: minimal. Cons: a retrying client that expects the reply gets nothing. Effort: Trivial. Risk: Medium (UX).

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `lib/virtuoso/conversation.ex`, `lib/virtuoso/conversation/log.ex`
  (may want a `fetch_outbound/2` by reply-id), `test/virtuoso/conversation_test.exs`
  (assert responder is NOT called on a duplicate — the existing dedup test only
  checks event count, not responder invocation).

## Acceptance Criteria
- [ ] A duplicate inbound does NOT invoke the responder.
- [ ] A duplicate inbound returns the originally-persisted reply.
- [ ] Test asserts the responder ran exactly once across two deliveries of the same message.

## Work Log
- Created from `/ce:review` of PR #64. Verified responder runs unconditionally in source.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64
- Plan: "exactly one reply and one billing event" (Phase-1 success criteria).

## Triage Decision (resolved)
**FIXED** (Solution A). `handle_call` now branches on the append status: a
`:duplicate` inbound short-circuits, returning the previously-logged reply via
new `Log.fetch_outbound/1`, and does NOT run the responder. Falls back to
`:noreply` if the crash-before-reply case left no logged outbound (that deeper
edge — architecture P2, replay an unanswered message — is noted but not in
scope here). New test proves the responder runs exactly once and the original
reply (not a divergent recomputation) is returned.
