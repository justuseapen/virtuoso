---
status: pending
priority: p3
issue_id: "011"
tags: [code-review, quality, cleanup, docs]
dependencies: []
---

# Small cleanups & doc fixes (batched)

## Problem Statement
A batch of low-risk cleanups and doc corrections surfaced across reviewers. Grouped
into one todo to avoid churn; each is independently applicable.

## Findings
1. **`LLM` moduledoc says `stream/2`** — the callback and function are `stream/3`.
   Public API doc an adapter author reads first. (`lib/virtuoso/llm.ex:~12-15`)
2. **`Impression.new/1` duplicates `@enforce_keys` enforcement** — `struct!/2`
   already raises on missing enforced keys; the separate `@required` attribute +
   manual `for ... raise ArgumentError` loop is a second source of truth for the
   same key list (violates "defaults in one place"). Keep only if the custom
   `ArgumentError` message is a real requirement; otherwise delete ~8 lines.
   (`lib/virtuoso/impression.ex:~44,55-61`)
3. **Dead `Log.count/0`** — test-only helper (0 non-def callers in `lib/`); inline
   into the test that needs it. (Keep `processed?/1` and `Budget.spent`/`global_spent`
   as deliberate operator introspection — the agent-native review actually wants MORE
   introspection, so these stay.) (`lib/virtuoso/conversation/log.ex:~107-109`)
4. **`Conversation.ensure_started/1` `Process.alive?` check is belt-and-suspenders** —
   the `:noproc` retry in `call/4` already covers the race. Optional simplification;
   the retry `catch` could also narrow from `[:noproc, :normal, :killed]` to just
   `:noproc` so a genuinely crashing responder surfaces instead of silently
   retrying once. (`lib/virtuoso/conversation.ex:~63-72,85-93`)
5. **`Anthropic.extract_system` silently drops a mid-list `:system` message** when
   there's no top-level `:system` and the system turn isn't the list head — a
   dropped system prompt is a subtle correctness bug. Either hoist any single
   `:system` regardless of position, or reject misplaced system turns explicitly.
   (`lib/virtuoso/llm/anthropic.ex:~91-108`)
6. **`from_status/3` `body \\ nil` default arg is unused** (only caller passes 3 args).
   Drop the default if no test relies on arity-2. (`lib/virtuoso/llm/error.ex:~43-44`)
7. **`Impression` `:version` moduledoc promises upgrade behavior that doesn't exist
   yet** — trim to "reserved for envelope evolution." (`lib/virtuoso/impression.ex:~10-13`)

## Proposed Solutions
Apply each independently; all Small/Trivial, Low risk. #5 (dropped system prompt)
is the only one with a correctness edge — prioritize it within this batch.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `llm.ex`, `impression.ex`, `conversation.ex`, `conversation/log.ex`,
  `llm/anthropic.ex`, `llm/error.ex`. Keep tests green; #5 wants a new test for a
  misplaced/absent system turn.

## Acceptance Criteria
- [ ] `stream/3` doc corrected.
- [ ] #5 (mid-list system message) either hoisted or explicitly rejected, with a test.
- [ ] Genuinely-dead `Log.count/0` removed (or a decision recorded to keep it).
- [ ] Remaining items applied or explicitly deferred with a note.

## Work Log
- Created from `/ce:review` of PR #64. Verified `Log.count`/`Budget.spent`/`global_spent`/`processed?` callers are test-only.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64

## Triage Decision
**DEFERRED** — Low-risk batch. Item #5 (Anthropic drops a mid-list system prompt) has a real correctness edge — worth doing soon; the rest are cosmetic. Fold into the next touch of these files.

## Partial Resolution (this pass)
- **#5 (Anthropic mid-list system prompt dropped) — FIXED.** `system_from_messages`
  now hoists a `:system` message from ANYWHERE in the list (Enum.find_value), not
  just the head; a mid-list system turn is no longer silently dropped. Test added.
- **#1 (stream/2 doc) — FIXED.** LLM moduledoc corrected to `stream/3`.
- **#3 (Log.count) — DECISION: keep.** Verified it's used by conversation/log tests
  as an assertion helper; not dead. Left in place.
- Remaining items (#2 Impression enforce-keys dup, #4 ensure_started belt-and-
  suspenders, #6 from_status default arg, #7 Impression :version prose) are
  cosmetic and left for a later touch of those files.
