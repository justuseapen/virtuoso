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

## Auth

The browser pipeline consults a host-provided plug on every request:

```elixir
config :virtuoso_dashboard, :auth, MyApp.AdminAuth
# or with options:
config :virtuoso_dashboard, :auth, {MyApp.BasicAuth, realm: "dashboard"}
```

Any plug works — e.g. `Plug.BasicAuth` wrapped in a module, or your app's
existing admin auth. Unset means **open access**: fine on localhost, never in
production.

Dev-only defaults elsewhere too: static secrets and `check_origin: false`.
Do not deploy as-is.

## PII policy

The dashboard never sees message content, by construction:

- **Transcripts live only in the event log** (`conversation_events` in the
  host's Postgres). Nothing here reads it.
- **Telemetry is shape-only.** LLM start/stop events carry counts, durations,
  model names, and token usage — no prompts, no completions. This is enforced
  by a test in the framework (`llm_test.exs`), not just convention.
- **Ensemble events carry decisions, not text.** The `decision` shown per run
  is a categorical routing label (a routine name), never user input.

So the dashboard can be shown on a team screen without leaking conversations —
the only trust boundary you must add is the auth plug above.
