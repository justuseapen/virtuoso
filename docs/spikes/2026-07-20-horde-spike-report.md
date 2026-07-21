# Horde spike — Phase 3 decision gate report

**Date:** 2026-07-20 · **Versions:** horde 0.10.0, Elixir 1.15.6, OTP 26.0.2
**Drill:** `test/distributed/horde_spike_test.exs` (`mix test --include distributed`)

## Question

Is Horde's registry consistent enough under node loss and netsplit to carry
Virtuoso's conversation processes, or do we fall back to `:global` + takeover /
Postgres-advisory-lock ownership? (Plan: Phase 3 spike, the flagged
highest-uncertainty dependency.)

## Method

Three scripted drills on a fresh 3-node local cluster per test (LocalCluster/
`:peer`), Horde.Registry + Horde.DynamicSupervisor with explicit 3-peer
membership, a minimal registered worker standing in for a conversation process:

1. **Visibility** — register on node A, measure until visible on B and C.
2. **Failover** — kill the host node, measure until the worker is restarted and
   registered on a survivor (plan target ≤ 5s).
3. **Netsplit** — partition membership {A,B} | {C}, register the *same* name on
   both sides, heal, verify exactly one survivor and uniform registry views.

## Results (final harness, 4/4 runs clean)

| Drill | Result | Plan target |
|---|---|---|
| Cross-node visibility | **204–307ms** | — |
| Failover after node kill | **52–307ms** | ≤ 5,000ms |
| Netsplit heal → one survivor, uniform views | **~0ms** after heal | no duplicate registrations |

## Findings

1. **Horde's happy path is far inside budget** — failover lands ~20–100× under
   the 5s target; registry merge after a heal resolves essentially instantly and
   always to exactly one survivor.
2. **The child-spec sync window is real.** The supervisor's child-spec CRDT
   syncs separately from the registry entry. A process whose node dies within
   ~1s of `start_child` may not be auto-restarted (survivors never learned the
   spec). Initial drill runs flaked ~50% on exactly this; a 1.5s settle
   eliminated it (4/4). **Architectural consequence: acceptable** — Virtuoso's
   recovery path is `ensure_started` + rehydrate-from-log on the next deliver;
   Horde redistribution is a warm-process optimization, not the correctness
   mechanism. The log's outbound dedup remains the exactly-once guarantee.
3. **Registry conflict resolution requires the `:ignore` pattern.** On heal, the
   registry kills the conflict loser; its `:permanent` supervisor immediately
   restarts it into a taken name. `start_link` must map
   `{:error, {:already_started, _}}` → `:ignore` (drilled in
   `DistHelper.Worker`); the production fabric's conversation `start_link` needs
   the same.
4. **Two in-VM simulation realities (harness, not Horde):** (a) dist-level
   splits can't be held open locally — any CRDT sync auto-reconnects Erlang
   distribution — so the drill partitions Horde's *membership* instead, which
   exercises the same merge code path; (b) OTP 25+'s `global` forcibly
   disconnects nodes on partial partitions and reads
   `prevent_overlapping_partitions` at boot only.
5. **Heal with a single `set_members` from the rejoining side.** Horde documents
   that one `set_members` propagates cluster-wide; issuing concurrent
   `set_members` from both sides of a heal creates conflicting membership-CRDT
   writes that churned convergence for tens of seconds (~50% drill flake).
   Single-sided heal converges in a steady ~255ms (6/6). Production `:auto`
   membership never takes the dual-write path.

## Verdict: **GO on Horde**

Proceed with Horde.Registry + Horde.DynamicSupervisor for the fabric. No
fallback needed. Carry findings 2 and 3 into the implementation:

- Conversation `start_link` maps `already_started` → `:ignore`.
- Document (and never rely against) the spec-sync window; recovery is
  log-rehydration by design.
- The drill stays in-tree as the scripted chaos drill the plan's quality gate
  requires.
