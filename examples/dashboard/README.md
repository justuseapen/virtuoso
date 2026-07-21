# Virtuoso Dashboard (example host app)

Dashboard v1 from the rebuild plan: **live ensemble runs — votes, dissent,
latency, cost per decision** — plus the LLM call stream and global budget
spend, fed entirely by the framework's documented telemetry
(`[:virtuoso, :ensemble, :run, :stop]`, `[:virtuoso, :llm, *, :stop]`).

This is a *host application*: the Virtuoso library stays Phoenix-free; this app
depends on it by path and observes it. Hand-rolled minimal Phoenix + LiveView —
no generators, no node/esbuild; the prebuilt JS ships inside the `phoenix` and
`phoenix_live_view` packages and is served straight from deps.

## Run it

Requires local Postgres (the framework's event log) — `mix ecto.setup` in the
repo root first if you haven't.

```sh
cd examples/dashboard
mix deps.get
mix run --no-halt
# open http://localhost:4040
```

Press **“Run demo ensemble”** — it fires a real `Ensemble.run/3` with the
framework's independently-noisy eval members (offline, no API key), and the
run's votes/dissent/cost stream onto the page live. Roughly a third of runs
show dissent or fall back, which is the interesting part.

Dev-only: static secrets, `check_origin: false`, no auth (a host-provided auth
plug is the Phase 4 item). Do not deploy as-is.
