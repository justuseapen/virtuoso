---
status: complete
priority: p1
issue_id: "002"
tags: [code-review, security, privacy, telemetry]
dependencies: []
---

# Full request (transcript + system prompt) emitted in LLM telemetry :start metadata

## Problem Statement
`Virtuoso.LLM.instrument/3` puts the entire `request` map — every user/assistant/
system message, the system prompt, and any `metadata` — into the `:start`
telemetry event metadata, on **every** LLM call. Any attached `:telemetry`
handler (a logger backend, a metrics/APM exporter, a vendor reporter) receives and
typically serializes the complete conversation content.

This directly contradicts the plan's stated intent that transcripts be redacted
from logs, and is a latent transcript-exfiltration path the moment anyone wires a
telemetry→log or telemetry→vendor handler. If a user pastes a secret into chat, or
the system prompt embeds a credential, it leaks wholesale.

Note: the API **key** itself is NOT leaked — it's threaded separately through
`opts`/headers and never enters `request`. The leak is prompt/PII content.

## Findings
- `lib/virtuoso/llm.ex:~133-136` (`:start` metadata `%{model: ..., request: request}`)
- Same pattern on the `:stream` path.
- Flagged P1 by security-sentinel; the raw `request` in metadata is confirmed.

## Proposed Solutions
### A. Emit only non-sensitive shape data (recommended)
`%{model: request.model, message_count: length(request.messages), has_system: request[:system] != nil}`.
- Pros: keeps telemetry useful for observability without transcript exposure; default-safe.
- Cons: debugging a specific prompt needs another path.
- Effort: Small. Risk: Low.

### B. Opt-in raw-request flag, default off
Gate the full request behind an explicit config flag documented as "logs transcripts."
- Pros: full fidelity when deliberately enabled.
- Cons: more surface; easy to leave on.
- Effort: Small. Risk: Low.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `lib/virtuoso/llm.ex` (`instrument/3` start metadata for both ops), `test/virtuoso/llm/telemetry_test.exs` (assert request body is NOT present, only shape).

## Acceptance Criteria
- [ ] `:start` metadata contains no message content or system prompt by default.
- [ ] Telemetry still carries `model` and enough shape to aggregate.
- [ ] Test asserts the raw `request`/messages are absent from default `:start` metadata.

## Work Log
- Created from `/ce:review` of PR #64.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64
- Plan: "transcripts redacted in telemetry/logs" (Phase 4 PII policy / non-functional criteria).

## Triage Decision (resolved)
**FIXED** (Solution A). `:start` telemetry metadata is now shape-only —
`%{model, message_count, has_system}` via `start_metadata/1`; the raw `request`
(messages, system prompt) is gone. Moduledoc updated. Test asserts `:request` is
absent and shape fields present.
