---
status: pending
priority: p3
issue_id: "008"
tags: [code-review, performance, database]
dependencies: ["005"]
---

# Composite (conversation_id, id) index for ordered replay

## Problem Statement
`events_for/1` filters `conversation_id == ?` and orders by `id asc`. The migration
indexes `conversation_id` alone, so Postgres index-scans on `conversation_id` then
**sorts** by `id`. A composite `(conversation_id, id)` index makes replay a pure
ordered range scan with no sort step — and it's the index that pairs with the
bounded `limit` from todo 005 to make rehydration a fast ordered read.

## Findings
- `lib/virtuoso/conversation/log.ex:~92-99` (filter + order_by id)
- `priv/repo/migrations/20260717163509_create_conversation_events.exs:~22` (single-col index)
- Flagged P2 by performance-oracle; downgraded to P3 (cheap, no correctness impact) and paired with 005.
- No N+1 or injection — queries are parameterized and single-shot (confirmed by security + perf).

## Proposed Solutions
### A. New migration adding composite index (recommended)
`create index(:conversation_events, [:conversation_id, :id])` and drop the
single-column `conversation_id` index (the composite serves the prefix lookup).
- Pros: eliminates the sort; one-line win. Cons: a second migration. Effort: Small. Risk: Low.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: new file under `priv/repo/migrations/`. Do NOT edit the existing
  migration (already applied) — add a new one.

## Acceptance Criteria
- [ ] Composite `(conversation_id, id)` index exists; replay needs no sort step.
- [ ] `mix ecto.migrate` runs clean.

## Work Log
- Created from `/ce:review` of PR #64.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64

## Triage Decision
**DEFERRED** — One-line index migration; do it together with 005 (bounded replay) so the two land as a unit.
