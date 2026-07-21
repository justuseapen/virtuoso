# Rolling deploys on the fabric

How to upgrade a clustered Virtuoso deployment without losing conversations or
double-sending replies. Single-node deployments can ignore this page — restart
freely; conversations rehydrate from the event log on the next message.

## The invariants that make rolling deploys safe

1. **State is derived from the log, never the sole copy.** A conversation
   process is a bounded working window over `conversation_events`; killing it
   loses nothing but warmth. Recovery = `ensure_started` + rehydrate on the next
   deliver, on whichever node that happens.
2. **Exactly-once is the log's job, not the cluster's.** Inbound dedup keys make
   webhook replays idempotent; outbound send-intent is recorded (dedup-keyed)
   before any channel send. Two nodes briefly owning the same conversation
   during a deploy cannot double-send by construction.
3. **`%Impression{}` is versioned** (`version: 1`). A newer node can recognize
   an older envelope shape during the window when both versions are live. When
   the struct changes, bump the version and accept both shapes for one release
   cycle before dropping the old one.

## Deploy procedure (fabric enabled)

1. **Drain before upgrade.** Stop routing new inbound traffic to the node being
   replaced (remove it from the load balancer / channel webhook targets). Let
   in-flight turns finish — a turn is seconds, not minutes; a short drain window
   (~30s) suffices. In-flight LLM/ensemble tasks on a killed node are abandoned;
   their cost is accepted and the message is re-processable (it is either
   unanswered in the log, or answered and dedup-protected).
2. **Stop the node.** Horde marks it down; its conversations restart on
   survivors (warm redistribution) or lazily on next deliver (rehydration).
   Note the spike finding: processes started < ~1s before the stop may not
   auto-redistribute — they recover via rehydration instead. Nothing is lost.
3. **Start the upgraded node.** libcluster joins it; Horde's `members: :auto`
   picks it up; new conversations distribute onto it.
4. **Repeat per node.** Never upgrade all nodes simultaneously — the Budget
   singleton needs a surviving host to fail over to (its counters reset on
   failover; the caps are protective ceilings, not billing records).

## Rules for code changes across a rolling window

- **Struct changes** (`Impression`, conversation state): additive first. Add
  fields with defaults in release N; rely on them in N+1. Never rename/remove
  in the same release that stops writing them.
- **Event-log schema**: migrations must be backward-compatible with the previous
  release (old nodes keep writing during the roll). Additive columns with
  defaults; contraction in a later release.
- **Ensemble/routine config**: routine registries are per-node code. During the
  window, a conversation may be routed by an old-config node and generated on a
  new one — keep routine *names* stable across releases; add new routines
  before routing to them.
