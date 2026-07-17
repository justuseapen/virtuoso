---
status: pending
priority: p3
issue_id: "009"
tags: [code-review, api, channel, agent-native]
dependencies: []
---

# Channel: send_out/2 is text-only (no media parity) and no channel-dispatch callback

## Problem Statement
Two coupled gaps in the `Virtuoso.Channel` behaviour, both about the outbound and
dispatch sides being thinner than the inbound side:

1. **No outbound media.** `translate_in/1` produces an `%Impression{}` carrying
   `media` + `metadata`, but `send_out/2` accepts only `reply_text :: String.t()`.
   Inbound is rich, outbound is text-only. A real channel that needs to reply with
   images/cards/quick-replies can't, without abusing the argument.
2. **No channel identity/dispatch.** An `%Impression{}` carries `channel: atom()`
   (`:web_chat`), but nothing maps that atom back to the adapter module for the
   reply path. The host must maintain an atom→module table by hand — the same
   implicit-registry problem `Virtuoso.Routine` was explicitly built to eliminate.

## Findings
- `lib/virtuoso/channel.ex:~34-35` (`send_out/2` text-only)
- `lib/virtuoso/channel/web_chat.ex:~45-47`
- `lib/virtuoso/channel.ex` (no `channel/0` callback / registry helper)
- `lib/virtuoso/conversation.ex` `commit_reply/3` only handles `{:reply, text}`.
- Flagged P2 by agent-native-reviewer; P3 here because Phase-1 scope is web-chat text only.

## Proposed Solutions
### A. Structured outbound reply + channel/0 callback (recommended, when a 2nd channel lands)
- Widen outbound to `%{text, media, metadata}` (or a trimmed impression); thread through `commit_reply`.
- Add `@callback channel() :: atom()` and a `Virtuoso.Channel` registry helper mirroring `Routine.fetch/2`.
- Pros: closes inbound→conversation→outbound loop programmatically; real media parity. Cons: larger; only needed once a second/richer channel exists. Effort: Medium. Risk: Low.

### B. Document Phase-1 scope (minimum now)
Note in the behaviour docs that outbound media and channel-registry dispatch are
deferred; web-chat is text + session-authenticated only.
- Pros: sets adapter-author expectations cheaply. Cons: defers the real work. Effort: Trivial. Risk: Low.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `lib/virtuoso/channel.ex`, `lib/virtuoso/channel/web_chat.ex`,
  `lib/virtuoso/conversation.ex` (`commit_reply`).

## Acceptance Criteria
- [ ] Either outbound carries media + a channel-dispatch mechanism exists, OR the Phase-1 text-only scope is documented in the behaviour.

## Work Log
- Created from `/ce:review` of PR #64.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64

## Triage Decision
**DEFERRED** — Only matters once a second/richer channel exists. Web-chat (Phase 1) is text + session-auth. Revisit when adding a media-capable channel.
