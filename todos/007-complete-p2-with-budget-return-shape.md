---
status: complete
priority: p2
issue_id: "007"
tags: [code-review, api, budget, ergonomics]
dependencies: []
---

# with_budget/3 return shape overloads :error across arities — refusal can't be cleanly matched

## Problem Statement
`with_budget/3` returns `{:ok, map()} | {:error, term()} | {:error, atom(), String.t()}`.
The `fun` returns 2-tuples (`{:ok, _}` / `{:error, reason}`), but a budget refusal
returns a **3-tuple** `{:error, reason, refusal_message}`. A caller pattern-matching
`{:error, reason}` silently fails to match the refusal — the exact case the
function exists to signal. An agent or host driving the framework can't write one
`case` that distinguishes a provider error from a budget refusal, because they
share the `:error` tag at different arities.

## Findings
- `lib/virtuoso/budget.ex:~97-108` (`with_budget` spec + refusal branch)
- Flagged P2 by agent-native-reviewer.

## Proposed Solutions
### A. Distinct tag for refusal (recommended)
Return `{:refused, reason, refusal_message()}` (or `{:error, {:budget, reason}, msg}`)
so refusal is unambiguous and both branches are matchable without arity confusion.
- Pros: clean single `case`; self-documenting. Cons: callers updated (few today). Effort: Small. Risk: Low.

### B. Always 3-arity error
Make provider errors `{:error, reason, nil}` too, uniform arity.
- Pros: uniform. Cons: awkward `nil`; still tag-overloaded. Effort: Small. Risk: Low.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `lib/virtuoso/budget.ex` (`with_budget`, `@spec`, docstring),
  `test/virtuoso/budget_test.exs` (the refusal-fallback test asserts the exact tuple — update it).

## Acceptance Criteria
- [ ] Budget refusal has a distinct leading tag, not `{:error, ...}` at a different arity.
- [ ] `@spec` and docstring updated.
- [ ] A single `case` can handle ok / provider-error / budget-refusal.

## Work Log
- Created from `/ce:review` of PR #64.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64

## Triage Decision
**DEFERRED** — Real API wart but with_budget/3 has no production callers yet (the thinking pipeline isn't wired). Cheap to fix later with zero migration cost; fix when the first real caller lands so the shape is validated against use.

## Resolution (complete — pre-publish)
**FIXED** with `{:refused, reason, refusal_message}` (Solution A). Done as a
Phase 4 pre-publish blocker: a Hex release creates external callers, after which
the arity-overloaded `:error` would calcify. Spec/docstring/Slow/tests updated.
