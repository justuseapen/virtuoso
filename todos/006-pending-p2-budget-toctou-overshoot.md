---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, correctness, budget, concurrency]
dependencies: []
---

# Budget check→record TOCTOU: concurrent calls overshoot the global cap

## Problem Statement
`with_budget/3` does `check/2` (permit) → run `fun` → `record/3` (add spend). Two
concurrent callers can both pass `check` while the global counter is just under the
cap, both run, then both `record` — so the global cap is exceeded by up to
(concurrency × per-call cost). The budget is described as "an Ensemble safety
property," and Phase 2's whole point is fan-out (N members per turn) — exactly the
concurrency that makes the overshoot equal the ensemble fan-out factor. The
acceptance criterion says "enforced, tested cost ceilings," but this is a soft
limit, not a ceiling.

## Findings
- `lib/virtuoso/budget.ex:~99-108` (`with_budget`: check, run, then record — no reservation)
- Converged: architecture (P2), performance (P2, also notes record needn't be synchronous).

## Proposed Solutions
### A. Reserve-then-reconcile (recommended)
`check` atomically reserves an estimated max (e.g. `max_tokens`) against the cap;
`record` reconciles the reservation to actual spend (releasing the delta).
- Pros: makes the cap a real ceiling under concurrency. Cons: needs a reservation ledger; slightly more state. Effort: Medium. Risk: Medium.

### B. Document as best-effort, make record a cast
Accept soft-limit semantics, update the docstring/plan wording, and make `record`
a `GenServer.cast` (its `:ok` is already discarded) to drop one hot-path round-trip.
- Pros: trivial; honest contract; small perf win. Cons: doesn't deliver a hard ceiling. Effort: Small. Risk: Low.

### C. ETS/:atomics counters (also addresses perf serialization)
Move counters to `:atomics`/`:counters`; `check` = lock-free read, `record` =
atomic increment. Combined with a compare-and-add this can enforce the cap without
a single-process bottleneck — the right shape before the Phase-3 cross-node singleton.
- Pros: removes serialization AND enables atomic enforcement. Cons: largest change. Effort: Large. Risk: Medium.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `lib/virtuoso/budget.ex`, `test/virtuoso/budget_test.exs` (add a concurrent-overshoot test).
- Related perf note: `record/3`'s result is unused → safe to `cast` regardless of chosen option.

## Acceptance Criteria
- [ ] Concurrent calls cannot exceed the global cap by more than one in-flight call (or the contract is explicitly documented as best-effort).
- [ ] Test exercises concurrent `with_budget` near the cap.

## Work Log
- Created from `/ce:review` of PR #64.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64
- Plan decision 4 (budget is an Ensemble safety property) + Phase-2 fan-out.

## Triage Decision
**DEFERRED** — The overshoot only bites under fan-out concurrency, which is Phase 2 (Ensemble). Best done WITH Phase 2 (reserve-then-reconcile, or ETS counters) so the design matches the fan-out workload. Not a single-node Phase-1 blocker.
