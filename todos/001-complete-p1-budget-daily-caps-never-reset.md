---
status: complete
priority: p1
issue_id: "001"
tags: [code-review, correctness, budget, otp]
dependencies: []
---

# Budget "daily" caps never reset — cap becomes a permanent outage

## Problem Statement
`Virtuoso.Budget` documents and exposes **daily** caps (`per_conversation_daily`,
`global_daily`; moduledoc "per-conversation daily caps", "global daily cap"), but
the counters only ever accumulate. There is no timer, no date bucketing, no
`Date.utc_today/0` key, no `Process.send_after` midnight reset. Verified: a grep
for `Date|utc_today|send_after|reset|midnight` in `budget.ex` returns nothing.

Consequence: once a cap is reached, every subsequent LLM call is refused
**forever** (until the process crashes/restarts). What is sold as a daily budget
is actually a process-lifetime budget. On a long-lived node this is a hard outage
with no spend, not a self-healing daily limit.

The plan (decision 4) and acceptance criteria ("enforced, tested cost ceilings —
per-message, per-conversation, global daily") explicitly require daily semantics.

## Findings
- `lib/virtuoso/budget.ex:31` (struct: `per_conversation: %{}`, `global: 0` — no date dimension)
- `lib/virtuoso/budget.ex:116-117` (`record` just adds; never buckets or evicts)
- `lib/virtuoso/budget.ex` — no reset mechanism anywhere
- Flagged P1 by architecture-strategist; confirmed against source.

## Proposed Solutions
### A. Bucket counters by UTC date (recommended)
Store `per_conversation` and `global` keyed by `Date.utc_today()`, and on
`check`/`record` compute against today's bucket; evict prior days lazily.
- Pros: correct daily semantics; no timer to supervise; naturally resets at UTC midnight.
- Cons: `Date.utc_today()` in the process — fine (not in a hot pure path).
- Effort: Small. Risk: Low.

### B. `Process.send_after` midnight reset
Schedule a reset message for the next UTC midnight that zeroes counters and reschedules.
- Pros: counters stay flat maps.
- Cons: a missed/late timer (node asleep, clock skew) leaves stale counters; more moving parts.
- Effort: Small. Risk: Medium.

### C. Rename to `*_cap` and drop the "daily" claim
If daily isn't actually wanted for v1, make the contract honest: lifetime caps.
- Pros: zero logic change; contract no longer lies.
- Cons: doesn't deliver what the plan requires; punts the real feature.
- Effort: Trivial. Risk: Low.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `lib/virtuoso/budget.ex`, `test/virtuoso/budget_test.exs` (add a reset test).

## Acceptance Criteria
- [ ] Reaching a cap refuses calls today but permits them again after the daily rollover.
- [ ] Test proves counters reset across a simulated date change (inject the "today" date).
- [ ] `check/2`/`record/3` operate on the current day's bucket.

## Work Log
- Created from `/ce:review` of PR #64. Confirmed no reset logic exists in source.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64
- Plan decision 4 (cluster-global budgeting) + Phase-1 acceptance criteria.

## Triage Decision (resolved)
**FIXED** (Solution A). Budget now tracks `day` (from an injectable `day_fun`,
default `Date.utc_today/0`) and zeroes counters on `check`/`record`/`spent`/
`global_spent` when the day rolls over. Also gave Budget a `child_spec/1` deriving
`:id` from `:name` so multiple budgets can co-supervise. 2 new tests (rollover
resets; same-day accumulates). Commit on branch.
