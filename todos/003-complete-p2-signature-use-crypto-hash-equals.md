---
status: complete
priority: p2
issue_id: "003"
tags: [code-review, security, crypto]
dependencies: []
---

# Hand-rolled secure_compare is not truly constant-time; use :crypto.hash_equals/2

## Problem Statement
`Virtuoso.Channel.Signature.valid?/3` verifies webhook HMACs, then compares with a
hand-rolled `secure_compare/2` (`:binary.bin_to_list |> Enum.zip |> Enum.reduce`)
guarded by a `byte_size` equality short-circuit. Two issues:

1. The `byte_size(expected) == byte_size(provided) and secure_compare(...)`
   short-circuits on length, so timing distinguishes "wrong length" from "right
   length, wrong bytes." **Low practical risk here** (expected is a fixed 64-char
   hex SHA-256 digest, so length is already known to an attacker) — but the module
   is presented as a *reusable* primitive, and a future caller comparing
   variable-length values inherits a real length-leak.
2. `secure_compare/2` runs at the Elixir/Enum level over freshly-allocated lists;
   it examines every byte (no early exit — good) but has no fixed instruction-count
   guarantee. The moduledoc calls it "constant-time," which overstates it.

The moduledoc declines `:crypto.hash_equals` "to stay dependency-free" — but
`:crypto` is ALREADY used one line up (`:crypto.mac/4`) and ships with OTP.
`:crypto.hash_equals/2` is confirmed available on this project's OTP 26. There is
no dependency cost avoided.

HMAC-SHA256 itself is the correct primitive — that part is fine.

## Findings
- `lib/virtuoso/channel/signature.ex:21` (`:crypto.mac` — crypto already a dep)
- `lib/virtuoso/channel/signature.ex:26` (length short-circuit)
- `lib/virtuoso/channel/signature.ex:34-40` (hand-rolled compare)
- Flagged by security (P2), performance (P3), simplicity, architecture (P3) — strong convergence.
- Verified `:crypto.hash_equals("abc","abc")` returns true on local OTP 26.

## Proposed Solutions
### A. Replace body with :crypto.hash_equals/2 (recommended)
```elixir
def valid?(payload, signature, secret) when is_binary(payload) and is_binary(signature) and is_binary(secret) do
  expected = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  :crypto.hash_equals(expected, strip_prefix(signature))
end
```
Drops `secure_compare/2` and the `byte_size` dance; handles unequal length internally without a distinguishable short-circuit; zero new deps.
- Pros: vetted OTP primitive, constant-time, less code. Cons: none material. Effort: Small. Risk: Low.

### B. Keep hand-rolled but compare raw 32-byte HMAC (not 64-char hex)
`Base.decode16(provided)` then compare raw bytes — half the work, still hand-rolled.
- Pros: no hex. Cons: still not guaranteed constant-time; keeps custom crypto code. Effort: Small. Risk: Medium.

## Recommended Action
_(fill during triage)_

## Technical Details
- Affected: `lib/virtuoso/channel/signature.ex`. Tests already cover the cases; they should stay green after the swap. Handle `strip_prefix` returning a non-hex/wrong-length string (hash_equals returns false, no crash).

## Acceptance Criteria
- [ ] `valid?/3` uses `:crypto.hash_equals/2`; `secure_compare/2` + `byte_size` guard removed.
- [ ] Existing signature tests (correct, prefixed, tampered, wrong-secret, malformed, empty) still pass.
- [ ] Moduledoc no longer claims a hand-rolled constant-time compare.

## Work Log
- Created from `/ce:review` of PR #64. Independently confirmed hash_equals availability before triage.

## Resources
- PR: https://github.com/justuseapen/virtuoso/pull/64
- `:crypto.hash_equals/2` (OTP 25+).

## Triage Decision (resolved)
**FIXED** (Solution A). `valid?/3` now uses `:crypto.hash_equals/2` (OTP-native
constant-time); `secure_compare/2` + `byte_size` guard removed. Confirmed
hash_equals raises ArgumentError on unequal length → rescued to `false`, so
malformed/empty signatures stay invalid (not a crash). All 6 signature tests green.
