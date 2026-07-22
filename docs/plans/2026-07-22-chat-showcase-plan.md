# Chat Showcase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deployed, public ChatGPT-like chat demo where every message runs
through Virtuoso's real pipeline and a live "under the hood" panel shows the
consensus machinery (route, votes, dissent, latency, cost, budget).

**Architecture:** The `examples/dashboard` Phoenix host app grows a `ChatLive`
page at `/` (ops dashboard moves to `/dashboard`, basic-auth'd in prod). A
`VirtuosoDashboard.Bot` (via `use Virtuoso.Bot`) routes between two generation
routines; replies arrive whole while ensemble telemetry animates the panel.
One additive framework change: `Ensemble.run/2` gains `:telemetry_meta` so
events carry `conversation_id` and the panel can filter to the viewer's own
conversation.

**Tech Stack:** Elixir 1.15.6-otp-26, Phoenix ~>1.7 + LiveView ~>1.0 (host app
only — library stays Phoenix-free), Postgres, Fly.io.

**Spec:** `docs/plans/2026-07-22-chat-showcase-design.md` (approved).

## Global Constraints

- Library core stays Phoenix-free; all web code lives in `examples/dashboard`.
- Telemetry stays shape-only: no message content in any event metadata.
  `conversation_id` is an opaque id, allowed.
- All root-repo gates must stay green: `mix format --check-formatted`,
  `mix test` (offline, needs local Postgres; run with
  `export PGUSER=justuseapen PGPASSWORD=""`), `mix credo --strict`,
  `mix dialyzer`, `mix compile --warnings-as-errors`. Dashboard app:
  `mix compile --warnings-as-errors` + its own `mix test`.
- Branch: `showcase/chat-demo` (already created; spec + this plan committed on it).
- Commit after every task (conventional commits, no attribution footer on
  incremental commits).
- Chat input hard cap: 500 chars. Engine panel keeps last 8 runs. Transcript
  rehydrates last 50 events.
- Default models (env-tunable in prod): routing `claude-haiku-4-5`
  (categorical votes — cheap ×N), generation `claude-opus-4-8`.

---

### Task 1: `Ensemble.run/2` `:telemetry_meta` passthrough (framework)

**Files:**
- Modify: `lib/virtuoso/ensemble.ex`
- Test: `test/virtuoso/ensemble_test.exs`

**Interfaces:**
- Produces: `Ensemble.run(request, opts)` accepts optional
  `telemetry_meta: map()`; every key appears in BOTH
  `[:virtuoso, :ensemble, :run, :start]` and `[..., :stop]` metadata. Reserved
  keys (`:strategy`, `:members_total`, `:outcome`, `:decision`, `:members_ok`,
  `:members_dropped`, `:usage`, `:count`, `:reason`) always win over
  `telemetry_meta` on conflict.

- [x] **Step 1: Write the failing test**

Append inside the existing
`describe "run/3 — usage + telemetry (the dashboard's feed)"` block of
`test/virtuoso/ensemble_test.exs` (it already defines `attach/1`, `members/1`,
`extract/0`, `usage_completion/3`):

```elixir
    test "telemetry_meta is merged into start and stop metadata" do
      attach([:virtuoso, :ensemble, :run, :start])
      attach([:virtuoso, :ensemble, :run, :stop])

      llm = fn _r, _o -> {:ok, usage_completion("route_x", 1, 1)} end

      opts = [
        members: members(["a", "b", "c"]),
        strategy: Majority,
        extract: extract(),
        llm: llm,
        telemetry_meta: %{conversation_id: "c-123", outcome: :spoofed}
      ]

      assert {:consensus, "route_x", _} = Ensemble.run(@base, opts)

      assert_received {:telemetry, [:virtuoso, :ensemble, :run, :start], _, start_meta}
      assert start_meta.conversation_id == "c-123"

      assert_received {:telemetry, [:virtuoso, :ensemble, :run, :stop], _, stop_meta}
      assert stop_meta.conversation_id == "c-123"
      # Reserved keys can't be spoofed by telemetry_meta.
      assert stop_meta.outcome == :consensus
    end
```

- [x] **Step 2: Run test to verify it fails**

Run: `export PGUSER=justuseapen PGPASSWORD="" && mix test test/virtuoso/ensemble_test.exs`
Expected: FAIL — `start_meta.conversation_id` raises `KeyError` (metadata has no such key).

- [x] **Step 3: Implement**

In `lib/virtuoso/ensemble.ex`, inside `run/2` after
`timeout = Keyword.get(opts, :timeout, 30_000)` add:

```elixir
    telemetry_meta = opts |> Keyword.get(:telemetry_meta, %{}) |> Map.new()
```

Change the start event to:

```elixir
    :telemetry.execute(
      [:virtuoso, :ensemble, :run, :start],
      %{system_time: System.system_time()},
      Map.merge(telemetry_meta, %{strategy: strategy, members_total: total})
    )
```

Change the stop event call to `stop_metadata(strategy, result, telemetry_meta)`
and the private function to:

```elixir
  defp stop_metadata(strategy, {outcome, decision_or_reason, meta}, telemetry_meta) do
    base = telemetry_meta |> Map.merge(meta) |> Map.merge(%{strategy: strategy})

    case outcome do
      :consensus -> Map.merge(base, %{outcome: :consensus, decision: decision_or_reason})
      :fallback -> Map.merge(base, %{outcome: :fallback, decision: decision_or_reason})
      :error -> Map.merge(base, %{outcome: :error, decision: nil, reason: decision_or_reason})
    end
  end
```

Document the option in the `@moduledoc` "## Options" list:

```
    * `:telemetry_meta` — map merged into run start/stop telemetry metadata
      (e.g. `%{conversation_id: id}`); reserved keys always win on conflict.
```

and add one line to the moduledoc "## Telemetry" section: metadata also
includes any caller-supplied `:telemetry_meta` keys.

- [x] **Step 4: Run tests to verify they pass**

Run: `export PGUSER=justuseapen PGPASSWORD="" && mix test test/virtuoso/ensemble_test.exs`
Expected: PASS (all tests in file).

- [x] **Step 5: Commit**

```bash
git add lib/virtuoso/ensemble.ex test/virtuoso/ensemble_test.exs
git commit -m "feat(ensemble): telemetry_meta passthrough on run start/stop events"
```

---

### Task 2: SlowThinking passes `conversation_id` into ensemble telemetry (framework)

**Files:**
- Modify: `lib/virtuoso/thinking/slow.ex`
- Test: `test/virtuoso/thinking/slow_test.exs`

**Interfaces:**
- Consumes: Task 1's `:telemetry_meta` option.
- Produces: every ensemble run triggered by the thinking pipeline carries
  `%{conversation_id: imp.conversation_id}` in its start/stop telemetry metadata.

- [x] **Step 1: Write the failing test**

Append a new test to `test/virtuoso/thinking/slow_test.exs`, reusing the
file's existing helpers for building impressions/opts (read the file first;
if it has no telemetry helper, use this self-contained test — adjust only the
opts construction to match the file's local conventions):

```elixir
  describe "telemetry" do
    test "routing runs carry the conversation_id" do
      handler = "slow-telemetry-#{inspect(make_ref())}"
      parent = self()

      :telemetry.attach(
        handler,
        [:virtuoso, :ensemble, :run, :stop],
        fn _name, _meas, meta, _ -> send(parent, {:run_stop, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      imp =
        Virtuoso.Impression.new(
          channel: :test,
          conversation_id: "slow-tel-1",
          sender_id: "u1",
          message_id: "m1",
          text: "route me"
        )

      routines = %{"echo" => __MODULE__.EchoRoutine}
      llm = fn _req, _opts ->
        {:ok, %{text: "echo", model: "m", stop_reason: :end_turn, usage: %{}, raw: %{}}}
      end

      assert {:reply, _} = Slow.respond(imp, %{}, routines: routines, llm: llm)

      assert_received {:run_stop, meta}
      assert meta.conversation_id == "slow-tel-1"
    end
  end

  defmodule EchoRoutine do
    @behaviour Virtuoso.Routine
    @impl true
    def run(_imp, _ctx), do: {:reply, "echoed"}
  end
```

(If `slow_test.exs` already defines an echo-style routine module, reuse it
instead of adding `EchoRoutine`.)

- [x] **Step 2: Run test to verify it fails**

Run: `export PGUSER=justuseapen PGPASSWORD="" && mix test test/virtuoso/thinking/slow_test.exs`
Expected: FAIL — `meta.conversation_id` raises `KeyError`.

- [x] **Step 3: Implement**

In `lib/virtuoso/thinking/slow.ex`, in `route/5`, add one entry to `run_opts`:

```elixir
    run_opts = [
      members: members(n, models),
      strategy: strategy,
      strategy_opts: strategy_opts,
      extract: &extract_route/1,
      llm: gate_llm(llm, budget, imp.conversation_id),
      telemetry_meta: %{conversation_id: imp.conversation_id}
    ]
```

- [x] **Step 4: Run tests, then all framework gates**

Run: `export PGUSER=justuseapen PGPASSWORD="" && mix test && mix format --check-formatted && mix credo --strict && mix dialyzer`
Expected: 174+ tests, 0 failures; credo/dialyzer/format clean.

- [x] **Step 5: Commit**

```bash
git add lib/virtuoso/thinking/slow.ex test/virtuoso/thinking/slow_test.exs
git commit -m "feat(thinking): conversation_id in ensemble run telemetry"
```

---

### Task 3: Dashboard test harness + Collector `conversation_id`

**Files:**
- Modify: `examples/dashboard/mix.exs` (elixirc_paths, aliases, floki dep)
- Modify: `examples/dashboard/config/config.exs` (test-env section)
- Modify: `examples/dashboard/lib/dashboard/collector.ex`
- Create: `examples/dashboard/test/test_helper.exs`
- Create: `examples/dashboard/test/support/llm_stub.ex`
- Test: `examples/dashboard/test/dashboard/collector_test.exs`

**Interfaces:**
- Produces: `VirtuosoDashboard.LLMStub` — a `Virtuoso.LLM` adapter used as
  `config :virtuoso, :llm` in the dashboard test env. Router requests (system
  contains `"Valid intents"`) return `"about_virtuoso"` when the last user
  message mentions "virtuoso" (case-insensitive), else `"answer"`. Generation
  requests return `"stub reply: " <> last_user_text`. Usage is always
  `%{input_tokens: 10, output_tokens: 5}`.
- Produces: Collector entries (both kinds) include `conversation_id:
  meta[:conversation_id]`.
- Produces: dashboard tests run against DB `virtuoso_dashboard_test` with the
  Ecto SQL sandbox; `mix test` in `examples/dashboard` creates/migrates it.

- [x] **Step 1: Wire the test env**

`examples/dashboard/mix.exs` — replace `project/0` and `deps/0`:

```elixir
  def project do
    [
      app: :virtuoso_dashboard,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]]
  end
```

and add to `deps/0`:

```elixir
      {:floki, ">= 0.34.0", only: :test}
```

Append to `examples/dashboard/config/config.exs`:

```elixir
if config_env() == :test do
  # Offline + isolated: stub adapter, sandboxed dedicated database, no server.
  config :virtuoso_dashboard, VirtuosoDashboardWeb.Endpoint, server: false

  config :virtuoso, :llm, VirtuosoDashboard.LLMStub

  config :virtuoso, Virtuoso.Repo,
    database: "virtuoso_dashboard_test",
    pool: Ecto.Adapters.SQL.Sandbox
end
```

Create `examples/dashboard/test/test_helper.exs`:

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Virtuoso.Repo, :manual)
```

Create `examples/dashboard/test/support/llm_stub.ex`:

```elixir
defmodule VirtuosoDashboard.LLMStub do
  @moduledoc """
  Offline `Virtuoso.LLM` adapter for dashboard tests. Cross-process safe
  (unlike the framework's process-scoped mock) because chat traffic spans
  conversation GenServers and ensemble tasks.
  """

  @behaviour Virtuoso.LLM

  @impl true
  def complete(request, _opts) do
    system = Map.get(request, :system)

    text =
      if is_binary(system) and String.contains?(system, "Valid intents") do
        if last_user_text(request) =~ ~r/virtuoso/i, do: "about_virtuoso", else: "answer"
      else
        "stub reply: " <> last_user_text(request)
      end

    {:ok,
     %{
       text: text,
       model: Map.get(request, :model, "stub"),
       stop_reason: :end_turn,
       usage: %{input_tokens: 10, output_tokens: 5},
       raw: %{}
     }}
  end

  @impl true
  def stream(request, on_chunk, opts) do
    {:ok, completion} = complete(request, opts)
    on_chunk.(%{done: completion})
    {:ok, completion}
  end

  defp last_user_text(%{messages: messages}) do
    messages |> List.last() |> Map.get(:content, "")
  end
end
```

- [x] **Step 2: Write the failing Collector test**

Create `examples/dashboard/test/dashboard/collector_test.exs`:

```elixir
defmodule VirtuosoDashboard.CollectorTest do
  use ExUnit.Case, async: false

  alias VirtuosoDashboard.Collector

  test "ensemble entries carry the conversation_id and broadcast on PubSub" do
    Phoenix.PubSub.subscribe(VirtuosoDashboard.PubSub, Collector.topic())

    :telemetry.execute(
      [:virtuoso, :ensemble, :run, :stop],
      %{duration: System.convert_time_unit(42, :millisecond, :native)},
      %{
        strategy: Virtuoso.Ensemble.Strategy.Majority,
        outcome: :consensus,
        decision: "answer",
        members_total: 3,
        members_ok: 3,
        count: 3,
        usage: %{input_tokens: 30, output_tokens: 15},
        conversation_id: "conv-tel-1"
      }
    )

    assert_receive {:ensemble_run, entry}, 1_000
    assert entry.conversation_id == "conv-tel-1"
    assert entry.decision == "answer"
    assert entry.dissent == 0
  end
end
```

- [x] **Step 3: Run to verify it fails**

Run: `cd examples/dashboard && export PGUSER=justuseapen PGPASSWORD="" && mix deps.get && mix test`
Expected: the collector test FAILS on `entry.conversation_id` (KeyError).
(`ecto.create`/`ecto.migrate` should succeed first — they run via the alias.)

- [x] **Step 4: Implement**

In `examples/dashboard/lib/dashboard/collector.ex`, add to BOTH entry maps
(`:ensemble_run` and `:llm_call`):

```elixir
      conversation_id: meta[:conversation_id],
```

- [x] **Step 5: Run tests to verify they pass**

Run: `cd examples/dashboard && export PGUSER=justuseapen PGPASSWORD="" && mix test && mix compile --warnings-as-errors && mix format --check-formatted`
Expected: PASS, clean compile/format.

- [x] **Step 6: Commit**

```bash
git add examples/dashboard
git commit -m "feat(showcase): dashboard test harness + conversation_id in collector entries"
```

---

### Task 4: The showcase bot — prompt files, fast path, generation routines

**Files:**
- Create: `examples/dashboard/priv/prompts/showcase/router.md`
- Create: `examples/dashboard/priv/prompts/showcase/answer.md`
- Create: `examples/dashboard/priv/prompts/showcase/about.md`
- Create: `examples/dashboard/lib/dashboard/bot/fast/greeting.ex`
- Create: `examples/dashboard/lib/dashboard/bot/generate.ex`
- Create: `examples/dashboard/lib/dashboard/bot/routines/answer.ex`
- Create: `examples/dashboard/lib/dashboard/bot/routines/about_virtuoso.ex`
- Create: `examples/dashboard/lib/dashboard/bot.ex`
- Modify: `examples/dashboard/config/config.exs` (chat model config)
- Test: `examples/dashboard/test/dashboard/bot_test.exs`

**Interfaces:**
- Consumes: `VirtuosoDashboard.LLMStub` semantics from Task 3;
  `Virtuoso.Bot.system/0`, `Virtuoso.Routine`, `Virtuoso.Thinking.Fast`,
  `Virtuoso.Budget.with_budget/3`, `Virtuoso.LLM.complete/2`.
- Produces: `VirtuosoDashboard.Bot.responder(opts \\ [])` — the responder
  ChatLive plugs into `Conversation.deliver`. Routine registry keys:
  `"answer"`, `"about_virtuoso"`. Greeting fast-thinker replies to
  hi/hello/hey/howdy/yo. Generation reads models from
  `Application.get_env(:virtuoso_dashboard, :chat)` keys `:routing_model`,
  `:generation_model`, `:max_tokens`.

- [x] **Step 1: Config + prompt files**

Append to `examples/dashboard/config/config.exs` (BEFORE the
`if config_env() == :test` block):

```elixir
# Chat showcase models (env-tunable in prod via runtime.exs). Routing is a
# categorical vote — cheap model ×N; generation is single-call quality.
config :virtuoso_dashboard, :chat,
  routing_model: "claude-haiku-4-5",
  generation_model: "claude-opus-4-8",
  max_tokens: 512
```

Create `examples/dashboard/priv/prompts/showcase/router.md`:

```markdown
You are the router for Virtuoso Chat, a public demo of the Virtuoso BEAM
AI-orchestration framework.

Pick "about_virtuoso" when the user is asking about Virtuoso itself — the
framework, how this demo works, ensembles, consensus, the BEAM, or this site.
Pick "answer" for everything else.

<!-- The framework appends the valid intent list and reply format after this
     preamble. -->
```

Create `examples/dashboard/priv/prompts/showcase/answer.md`:

```markdown
You are Virtuoso Chat, a friendly, concise assistant demoing the Virtuoso
framework. Answer helpfully in a few sentences. You cannot browse the web or
run code. If asked what you are, mention you run on Virtuoso, a BEAM-native
AI-orchestration framework, and that the panel beside the chat shows the
consensus machinery live.
```

Create `examples/dashboard/priv/prompts/showcase/about.md`:

```markdown
You are Virtuoso Chat answering questions about the Virtuoso framework itself.

Facts you may draw on: Virtuoso is a BEAM-native AI-agent orchestration
framework in Elixir/OTP. Its flagship is actor-based parallel consensus:
N lightweight processes query LLMs concurrently and vote on structured
decisions (majority/quorum/judge); voting is on decisions, never free text, and
side effects run exactly once after consensus. Conversations are one process
each, backed by an append-only Postgres event log with dedup keys
(exactly-once). An optional Horde-based fabric distributes conversations
across a cluster with automatic failover. Every message in this demo routes
through a real 3-member ensemble — the panel beside the chat shows the votes.
Source: github.com/justuseapen/virtuoso.

Answer concisely and concretely. If you don't know, say so.
```

- [x] **Step 2: Write the failing tests**

Create `examples/dashboard/test/dashboard/bot_test.exs`:

```elixir
defmodule VirtuosoDashboard.BotTest do
  use ExUnit.Case, async: false

  alias Virtuoso.Impression
  alias VirtuosoDashboard.Bot

  defp imp(text) do
    Impression.new(
      channel: :web,
      conversation_id: "bot-test-#{System.unique_integer([:positive])}",
      sender_id: "visitor",
      message_id: "m-#{System.unique_integer([:positive])}",
      text: text
    )
  end

  defp attach_run_stop do
    handler = "bot-test-#{inspect(make_ref())}"
    parent = self()

    :telemetry.attach(
      handler,
      [:virtuoso, :ensemble, :run, :stop],
      fn _n, _m, meta, _ -> send(parent, {:run_stop, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  test "greetings take the fast path — zero LLM calls" do
    attach_run_stop()
    assert {:reply, reply} = Bot.responder().(imp("hi"), [])
    assert reply =~ "Virtuoso"
    refute_received {:run_stop, _}
  end

  test "general questions route to answer and generate via the LLM" do
    attach_run_stop()
    assert {:reply, reply} = Bot.responder().(imp("what is the capital of france"), [])
    assert reply == "stub reply: what is the capital of france"
    assert_received {:run_stop, %{decision: "answer"}}
  end

  test "framework questions route to about_virtuoso" do
    attach_run_stop()
    assert {:reply, _} = Bot.responder().(imp("how does virtuoso vote?"), [])
    assert_received {:run_stop, %{decision: "about_virtuoso"}}
  end

  test "generation includes bounded history as messages" do
    history = [{:user, "earlier question"}, {:assistant, "earlier answer"}]
    assert {:reply, "stub reply: follow-up"} = Bot.responder().(imp("follow-up"), history)
  end

  test "a refused budget turns into the framework refusal message" do
    start_supervised!({Virtuoso.Budget, name: :bot_test_budget, global_daily: 0})
    assert {:reply, reply} = Bot.responder(budget: :bot_test_budget).(imp("anything"), [])
    assert reply == Virtuoso.Budget.refusal_message()
  end
end
```

- [x] **Step 3: Run to verify failure**

Run: `cd examples/dashboard && export PGUSER=justuseapen PGPASSWORD="" && mix test test/dashboard/bot_test.exs`
Expected: FAIL — `VirtuosoDashboard.Bot` is undefined.

- [x] **Step 4: Implement the bot**

Create `examples/dashboard/lib/dashboard/bot/fast/greeting.ex`:

```elixir
defmodule VirtuosoDashboard.Bot.Fast.Greeting do
  @moduledoc "Zero-token greeting matcher — the demo's visible fast path."

  @behaviour Virtuoso.Thinking.Fast

  alias Virtuoso.Impression

  @greetings ~w(hi hello hey howdy yo)

  @impl true
  def match(%Impression{text: text}, _context) when is_binary(text) do
    if String.downcase(String.trim(text)) in @greetings do
      {:match,
       {:reply,
        "Hello! I'm Virtuoso Chat. This greeting took the deterministic fast " <>
          "path — zero tokens. Ask me anything and watch the ensemble vote " <>
          "in the panel."}}
    else
      :no_match
    end
  end

  def match(_impression, _context), do: :no_match
end
```

Create `examples/dashboard/lib/dashboard/bot/generate.ex`:

```elixir
defmodule VirtuosoDashboard.Bot.Generate do
  @moduledoc """
  Shared single-model generation for the showcase routines. Runs exactly once,
  post-consensus, budget-gated. History comes from the conversation process
  (oldest-first `{role, content}` tuples).
  """

  alias Virtuoso.{Budget, Impression, LLM}

  @history_window 20
  @error_reply "I hit a snag talking to the model — please try again in a moment."

  @spec reply(Impression.t(), map(), String.t()) :: {:reply, String.t()}
  def reply(%Impression{} = imp, context, system) do
    chat = Application.get_env(:virtuoso_dashboard, :chat, [])

    request = %{
      model: Keyword.get(chat, :generation_model, "claude-opus-4-8"),
      system: system,
      max_tokens: Keyword.get(chat, :max_tokens, 512),
      messages: history_messages(context) ++ [%{role: :user, content: imp.text || ""}]
    }

    case Budget.with_budget(imp.conversation_id, fn -> LLM.complete(request) end) do
      {:ok, %{text: text}} -> {:reply, text}
      {:refused, _reason, refusal} -> {:reply, refusal}
      {:error, _error} -> {:reply, @error_reply}
    end
  end

  defp history_messages(context) do
    context
    |> Map.get(:history, [])
    |> Enum.filter(fn {_role, content} -> is_binary(content) end)
    |> Enum.take(-@history_window)
    |> Enum.map(fn {role, content} -> %{role: normalize_role(role), content: content} end)
  end

  # Log-rehydrated roles may be strings; live ones are atoms.
  defp normalize_role(role) when role in [:user, "user"], do: :user
  defp normalize_role(_role), do: :assistant
end
```

Create `examples/dashboard/lib/dashboard/bot/routines/answer.ex`:

```elixir
defmodule VirtuosoDashboard.Bot.Routines.Answer do
  @moduledoc "General chat generation — the \"answer\" route."

  @behaviour Virtuoso.Routine

  alias VirtuosoDashboard.Bot.Generate

  @prompt_path "priv/prompts/showcase/answer.md"
  @external_resource @prompt_path
  @prompt File.read!(@prompt_path)

  @impl true
  def run(impression, context), do: Generate.reply(impression, context, @prompt)
end
```

Create `examples/dashboard/lib/dashboard/bot/routines/about_virtuoso.ex`:

```elixir
defmodule VirtuosoDashboard.Bot.Routines.AboutVirtuoso do
  @moduledoc "Answers questions about the framework — the \"about_virtuoso\" route."

  @behaviour Virtuoso.Routine

  alias VirtuosoDashboard.Bot.Generate

  @prompt_path "priv/prompts/showcase/about.md"
  @external_resource @prompt_path
  @prompt File.read!(@prompt_path)

  @impl true
  def run(impression, context), do: Generate.reply(impression, context, @prompt)
end
```

Create `examples/dashboard/lib/dashboard/bot.ex`:

```elixir
defmodule VirtuosoDashboard.Bot do
  @moduledoc """
  The showcase bot: greeting fast path, then a real 3-member ensemble votes on
  the route ("answer" vs "about_virtuoso") and the winning routine generates
  once.
  """

  use Virtuoso.Bot

  @router_prompt_path "priv/prompts/showcase/router.md"
  @external_resource @router_prompt_path
  @router_prompt File.read!(@router_prompt_path)

  @impl true
  def system, do: @router_prompt

  @impl true
  def fast, do: [VirtuosoDashboard.Bot.Fast.Greeting]

  @impl true
  def routines do
    %{
      "answer" => VirtuosoDashboard.Bot.Routines.Answer,
      "about_virtuoso" => VirtuosoDashboard.Bot.Routines.AboutVirtuoso
    }
  end

  @impl true
  def ensemble do
    chat = Application.get_env(:virtuoso_dashboard, :chat, [])
    [n: 3, strategy: :majority, models: [Keyword.get(chat, :routing_model, "claude-haiku-4-5")]]
  end
end
```

- [x] **Step 5: Run tests to verify they pass**

Run: `cd examples/dashboard && export PGUSER=justuseapen PGPASSWORD="" && mix test && mix compile --warnings-as-errors && mix format --check-formatted`
Expected: PASS. If the refusal test fails because the routine (not the turn
gate) sees the default budget: note that the turn-level gate in
`Slow.respond/3` uses the `:budget` opt — the test passes it via
`Bot.responder(budget: :bot_test_budget)`, which reaches Slow through the
responder's option passthrough, so the turn is refused before any member runs.

- [x] **Step 6: Commit**

```bash
git add examples/dashboard
git commit -m "feat(showcase): bot with prompt files, fast greeting, ensemble-routed generation"
```

---

### Task 5: ChatLive — chat UI + engine panel + session identity

**Files:**
- Modify: `examples/dashboard/lib/dashboard_web/router.ex`
- Modify: `examples/dashboard/lib/dashboard_web/layouts.ex` (add chat CSS)
- Create: `examples/dashboard/lib/dashboard_web/chat_live.ex`
- Test: `examples/dashboard/test/dashboard_web/chat_live_test.exs`

**Interfaces:**
- Consumes: `VirtuosoDashboard.Bot.responder/1` (Task 4), Collector PubSub
  entries with `conversation_id` (Task 3), `Virtuoso.Conversation.deliver/2`,
  `Virtuoso.Conversation.Log.recent_events_for/2` (chronological,
  oldest-first — same as `Conversation.init/1` uses), `Virtuoso.Budget.spent/2`
  and `global_spent/1`.
- Produces: `/` renders ChatLive; `/dashboard` renders the existing
  DashboardLive; the browser pipeline seeds `"conversation_id"` in the session.
  The `:admin` pipeline (auth hook) wraps `/dashboard` only.

- [x] **Step 1: Write the failing LiveView test**

Create `examples/dashboard/test/dashboard_web/chat_live_test.exs`:

```elixir
defmodule VirtuosoDashboardWeb.ChatLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint VirtuosoDashboardWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Virtuoso.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Virtuoso.Repo, {:shared, self()})
    {:ok, conn: build_conn()}
  end

  # PubSub → LiveView delivery is async; poll briefly instead of sleeping.
  defp eventually(fun, tries \\ 50) do
    if fun.() do
      :ok
    else
      if tries == 0, do: flunk("condition never became true")
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  test "chat: send a message, get the stubbed reply, see the run card", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "Virtuoso Chat"

    view
    |> form("#chat-form", chat: %{text: "hello world"})
    |> render_submit()

    # The user's message renders immediately.
    assert render(view) =~ "hello world"

    # The async deliver completes with the stub reply.
    assert render_async(view, 5_000) =~ "stub reply: hello world"

    # The engine panel shows this conversation's run (decision + votes).
    eventually(fn -> render(view) =~ "answer" and render(view) =~ "3/3" end)
  end

  test "greeting renders a fast-path card, not an ensemble run", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> form("#chat-form", chat: %{text: "hi"}) |> render_submit()

    assert render_async(view, 5_000) =~ "fast path"
  end

  test "transcript survives a reload via the event log", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> form("#chat-form", chat: %{text: "remember me"}) |> render_submit()
    assert render_async(view, 5_000) =~ "stub reply: remember me"

    # Same conn = same session cookie = same conversation_id.
    {:ok, _view2, html2} = live(conn, "/")
    assert html2 =~ "remember me"
    assert html2 =~ "stub reply: remember me"
  end

  test "dashboard still renders at /dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/dashboard")
    assert html =~ "live ensemble dashboard"
  end
end
```

- [x] **Step 2: Run to verify failure**

Run: `cd examples/dashboard && export PGUSER=justuseapen PGPASSWORD="" && mix test test/dashboard_web/chat_live_test.exs`
Expected: FAIL — no route `/` for ChatLive (undefined module).

- [x] **Step 3: Router + session identity**

Replace `examples/dashboard/lib/dashboard_web/router.ex` contents:

```elixir
defmodule VirtuosoDashboardWeb.Router do
  use Phoenix.Router, helpers: false

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_root_layout, html: {VirtuosoDashboardWeb.Layouts, :root}
    plug :put_conversation_id
  end

  # The ops dashboard is auth-gated (host-provided plug); chat is public.
  pipeline :admin do
    plug :dashboard_auth
  end

  scope "/", VirtuosoDashboardWeb do
    pipe_through :browser

    live "/", ChatLive
  end

  scope "/", VirtuosoDashboardWeb do
    pipe_through [:browser, :admin]

    live "/dashboard", DashboardLive
  end

  # Every visitor gets a stable per-browser conversation id — the identity the
  # event log, budget caps, and engine panel all key on.
  defp put_conversation_id(conn, _opts) do
    case get_session(conn, "conversation_id") do
      nil ->
        id = "web-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
        put_session(conn, "conversation_id", id)

      _id ->
        conn
    end
  end

  # Host-provided auth hook: point the config at any plug and every dashboard
  # request goes through it before rendering.
  #
  #     config :virtuoso_dashboard, :auth, MyApp.AdminAuth
  #     config :virtuoso_dashboard, :auth, {MyApp.BasicAuth, realm: "dashboard"}
  #
  # Unset → open access (dev only; the README says so out loud).
  defp dashboard_auth(conn, _opts) do
    case Application.get_env(:virtuoso_dashboard, :auth) do
      nil -> conn
      {plug, opts} -> plug.call(conn, plug.init(opts))
      plug when is_atom(plug) -> plug.call(conn, plug.init([]))
    end
  end
end
```

- [x] **Step 4: ChatLive**

Create `examples/dashboard/lib/dashboard_web/chat_live.ex`:

```elixir
defmodule VirtuosoDashboardWeb.ChatLive do
  @moduledoc """
  The showcase: a ChatGPT-like chat whose every message runs the real Virtuoso
  pipeline, beside a live "under the hood" panel fed by ensemble telemetry
  filtered to this visitor's conversation.
  """

  use Phoenix.LiveView

  alias Virtuoso.{Budget, Conversation, Impression}
  alias Virtuoso.Conversation.Log
  alias VirtuosoDashboard.Collector

  @max_input 500
  @keep_runs 8
  @transcript_window 50

  @impl true
  def mount(_params, session, socket) do
    conversation_id = Map.fetch!(session, "conversation_id")

    if connected?(socket) do
      Phoenix.PubSub.subscribe(VirtuosoDashboard.PubSub, Collector.topic())
    end

    {:ok,
     socket
     |> assign(
       conversation_id: conversation_id,
       messages: transcript(conversation_id),
       pending: false,
       runs: [],
       runs_at_send: 0
     )
     |> assign_budget()}
  end

  @impl true
  def handle_event("send", %{"chat" => %{"text" => text}}, socket) do
    text = text |> String.trim() |> String.slice(0, @max_input)

    if text == "" or socket.assigns.pending do
      {:noreply, socket}
    else
      imp =
        Impression.new(
          channel: :web,
          conversation_id: socket.assigns.conversation_id,
          sender_id: socket.assigns.conversation_id,
          message_id: "web-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false),
          text: text
        )

      responder = VirtuosoDashboard.Bot.responder()

      {:noreply,
       socket
       |> assign(pending: true, runs_at_send: length(socket.assigns.runs))
       |> update(:messages, &(&1 ++ [%{role: :user, text: text}]))
       |> start_async(:reply, fn -> Conversation.deliver(imp, responder: responder) end)}
    end
  end

  @impl true
  def handle_async(:reply, {:ok, result}, socket) do
    socket =
      case result do
        {:reply, text} -> update(socket, :messages, &(&1 ++ [%{role: :assistant, text: text}]))
        :noreply -> socket
      end

    # No new ensemble run since send → this was the deterministic fast path.
    # (The run's PubSub message beats the async result into our mailbox, so
    # this check is ordered, not racy.)
    socket =
      if length(socket.assigns.runs) == socket.assigns.runs_at_send do
        update(socket, :runs, &Enum.take([%{fast_path: true, at: DateTime.utc_now()} | &1], @keep_runs))
      else
        socket
      end

    {:noreply, socket |> assign(pending: false) |> assign_budget()}
  end

  def handle_async(:reply, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(pending: false)
     |> update(:messages, &(&1 ++ [%{role: :assistant, text: "Something went wrong — please try again."}]))}
  end

  @impl true
  def handle_info({:ensemble_run, entry}, socket) do
    if entry.conversation_id == socket.assigns.conversation_id do
      {:noreply,
       socket
       |> update(:runs, &Enum.take([entry | &1], @keep_runs))
       |> assign_budget()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:llm_call, _entry}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="chat-page">
      <section class="chat-pane">
        <h1>Virtuoso Chat</h1>
        <p class="sub">
          every message routes through a real LLM ensemble — watch it think ➔
        </p>

        <div class="messages" id="messages">
          <div :for={msg <- @messages} class={"msg #{msg.role}"}>
            <span class="who">{if msg.role == :user, do: "you", else: "virtuoso"}</span>
            <p>{msg.text}</p>
          </div>
          <div :if={@pending} class="msg assistant thinking">
            <span class="who">virtuoso</span>
            <p>thinking…</p>
          </div>
        </div>

        <form id="chat-form" phx-submit="send">
          <input
            type="text"
            name="chat[text]"
            value=""
            maxlength="500"
            placeholder="say hi, or ask anything…"
            autocomplete="off"
            disabled={@pending}
          />
          <button type="submit" disabled={@pending}>send</button>
        </form>
      </section>

      <aside class="engine-pane">
        <h2>under the hood</h2>
        <p class="sub">
          live from <code>[:virtuoso, :ensemble, :run, :stop]</code> — your
          conversation only
        </p>

        <div :for={run <- @runs} class="run-card">
          <%= if run[:fast_path] do %>
            <b class="ok">fast path</b>
            <span>deterministic match — 0 tokens, no LLM</span>
          <% else %>
            <b class={if run.outcome == :consensus, do: "ok", else: "warn"}>{run.outcome}</b>
            <span>route: <code>{run.decision || "—"}</code></span>
            <span>votes: {run.count || "–"}/{run.members_ok} · dissent: {run.dissent || 0}</span>
            <span>{run.duration_ms}ms · {tokens(run.usage)} tokens</span>
          <% end %>
        </div>
        <p :if={@runs == []} class="empty">send a message to see the ensemble vote</p>

        <h2>budget</h2>
        <div class="budget-row">
          <span>you</span> <b>{@budget.mine}</b> / {cap(@budget.mine_cap)}
        </div>
        <div class="budget-row">
          <span>everyone today</span> <b>{@budget.global}</b> / {cap(@budget.global_cap)}
        </div>
        <p class="sub">
          caps enforced by <code>Virtuoso.Budget</code> — when they're hit, the
          bot refuses politely instead of spending.
        </p>

        <p class="sub">
          <a href="https://github.com/justuseapen/virtuoso">github.com/justuseapen/virtuoso</a>
          · <a href="/dashboard">ops dashboard</a>
        </p>
      </aside>
    </div>
    """
  end

  # Rebuild the transcript from the event log (chronological) — the log
  # demoing itself across refreshes.
  defp transcript(conversation_id) do
    conversation_id
    |> Log.recent_events_for(@transcript_window)
    |> Enum.map(&%{role: role_atom(&1.role), text: &1.content})
    |> Enum.filter(&is_binary(&1.text))
  end

  defp role_atom(role) when role in [:user, "user"], do: :user
  defp role_atom(_role), do: :assistant

  defp assign_budget(socket) do
    caps = Application.get_env(:virtuoso, Virtuoso.Budget, [])

    assign(socket,
      budget: %{
        mine: Budget.spent(socket.assigns.conversation_id),
        mine_cap: Keyword.get(caps, :per_conversation_daily, :infinity),
        global: Budget.global_spent(),
        global_cap: Keyword.get(caps, :global_daily, :infinity)
      }
    )
  end

  defp tokens(%{input_tokens: i, output_tokens: o}), do: i + o
  defp tokens(_usage), do: 0

  defp cap(:infinity), do: "∞"
  defp cap(n), do: n
end
```

- [x] **Step 5: Chat CSS**

In `examples/dashboard/lib/dashboard_web/layouts.ex`, inside the existing
`<style>` block, append:

```css
.chat-page { display: grid; grid-template-columns: minmax(0, 2fr) minmax(260px, 1fr);
             gap: 2rem; max-width: 1100px; }
@media (max-width: 800px) { .chat-page { grid-template-columns: 1fr; } }
.messages { display: flex; flex-direction: column; gap: 0.5rem; margin: 1rem 0;
            min-height: 300px; }
.msg { max-width: 85%; padding: 0.5rem 0.75rem; border-radius: 8px; }
.msg p { margin: 0.15rem 0 0; white-space: pre-wrap; }
.msg .who { font-size: 0.7rem; color: #616e88; }
.msg.user { align-self: flex-end; background: #2e3440; }
.msg.assistant { align-self: flex-start; background: #1c2230; }
.msg.thinking p { color: #616e88; font-style: italic; }
#chat-form { display: flex; gap: 0.5rem; }
#chat-form input { flex: 1; background: #1c2230; color: #d8dee9; border: 1px solid #2e3440;
                   border-radius: 4px; padding: 0.5rem 0.75rem; font: inherit; }
.run-card { display: flex; flex-direction: column; gap: 0.15rem; font-size: 0.78rem;
            border: 1px solid #2e3440; border-radius: 6px; padding: 0.5rem 0.7rem;
            margin-bottom: 0.5rem; }
.budget-row { font-size: 0.8rem; margin-bottom: 0.25rem; }
.budget-row b { color: #88c0d0; }
a { color: #81a1c1; }
```

Also change the `<title>` to `Virtuoso — chat showcase`.

- [x] **Step 6: Run tests**

Run: `cd examples/dashboard && export PGUSER=justuseapen PGPASSWORD="" && mix test && mix compile --warnings-as-errors && mix format --check-formatted`
Expected: PASS, all dashboard tests.

- [x] **Step 7: Manual smoke test**

Run: `cd examples/dashboard && mix run --no-halt` then open
`http://localhost:4040` — say "hi" (fast-path card), ask a question (with
`ANTHROPIC_API_KEY` set: real reply + run card; without: friendly error reply),
refresh (transcript persists), open `/dashboard` (runs visible globally).
Kill the server when done (`Ctrl-C` / `pkill -f "mix run --no-halt"`).

- [x] **Step 8: Commit**

```bash
git add examples/dashboard
git commit -m "feat(showcase): ChatLive — chat with live ensemble engine panel"
```

---

### Task 6: Production deployment artifacts (Fly.io)

**Files:**
- Create: `examples/dashboard/config/runtime.exs`
- Create: `examples/dashboard/lib/dashboard_web/basic_auth.ex`
- Create: `examples/dashboard/lib/dashboard/release.ex`
- Create: `examples/dashboard/Dockerfile`
- Create: `examples/dashboard/fly.toml`
- Modify: `examples/dashboard/README.md`

**Interfaces:**
- Consumes: the `:auth` hook (router), `Virtuoso.Migrations` (0.1.0),
  `config :virtuoso, Virtuoso.Budget` caps, `:virtuoso_dashboard, :chat`
  model config.
- Produces: a release-ready app. Required prod env/secrets:
  `SECRET_KEY_BASE`, `DATABASE_URL`, `ANTHROPIC_API_KEY`,
  `DASHBOARD_PASSWORD`; optional: `PHX_HOST`, `PORT`, `POOL_SIZE`,
  `BUDGET_PER_CONVERSATION_DAILY` (default 10000), `BUDGET_GLOBAL_DAILY`
  (default 500000), `DASHBOARD_USER` (default "admin"), `ROUTING_MODEL`,
  `GENERATION_MODEL`.

- [x] **Step 1: Runtime config**

Create `examples/dashboard/config/runtime.exs`:

```elixir
import Config

if config_env() == :prod do
  host = System.get_env("PHX_HOST", "virtuoso-showcase.fly.dev")
  port = String.to_integer(System.get_env("PORT", "8080"))

  config :virtuoso_dashboard, VirtuosoDashboardWeb.Endpoint,
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    check_origin: ["https://#{host}"],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    server: true

  config :virtuoso, Virtuoso.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :virtuoso, Virtuoso.LLM.Anthropic,
    api_key: {:system, "ANTHROPIC_API_KEY"}

  # The public demo's spend ceiling. Tune without redeploying.
  config :virtuoso, Virtuoso.Budget,
    per_conversation_daily:
      String.to_integer(System.get_env("BUDGET_PER_CONVERSATION_DAILY", "10000")),
    global_daily: String.to_integer(System.get_env("BUDGET_GLOBAL_DAILY", "500000"))

  # Ops dashboard behind basic auth; chat stays public.
  config :virtuoso_dashboard, :auth,
    {VirtuosoDashboardWeb.BasicAuth,
     username: System.get_env("DASHBOARD_USER", "admin"),
     password: System.fetch_env!("DASHBOARD_PASSWORD")}

  config :virtuoso_dashboard, :chat,
    routing_model: System.get_env("ROUTING_MODEL", "claude-haiku-4-5"),
    generation_model: System.get_env("GENERATION_MODEL", "claude-opus-4-8"),
    max_tokens: 512
end
```

- [x] **Step 2: Basic auth plug + release migrator**

Create `examples/dashboard/lib/dashboard_web/basic_auth.ex`:

```elixir
defmodule VirtuosoDashboardWeb.BasicAuth do
  @moduledoc "HTTP basic auth for the ops dashboard (plugged via the :auth hook)."

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts), do: Plug.BasicAuth.basic_auth(conn, opts)
end
```

Create `examples/dashboard/lib/dashboard/release.ex`:

```elixir
defmodule VirtuosoDashboard.Release do
  @moduledoc "Release tasks — run via `bin/virtuoso_dashboard eval`."

  @doc "Bring the database to the current Virtuoso schema (Fly release_command)."
  def migrate do
    Application.ensure_all_started(:ssl)
    Application.load(:virtuoso)

    {:ok, _fun_return, _apps} =
      Ecto.Migrator.with_repo(Virtuoso.Repo, fn repo ->
        Ecto.Migrator.run(repo, [{20_260_722_000_000, Virtuoso.Migrations}], :up, all: true)
      end)
  end
end
```

- [x] **Step 3: Dockerfile + fly.toml**

Create `examples/dashboard/Dockerfile` (build context = **repo root**, because
of the `{:virtuoso, path: "../.."}` dep):

```dockerfile
FROM hexpm/elixir:1.15.6-erlang-26.0.2-debian-bookworm-20240701-slim AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /src
# The framework (path dep) …
COPY mix.exs mix.lock ./
COPY lib lib
COPY priv priv
# … and the showcase app.
COPY examples/dashboard examples/dashboard

WORKDIR /src/examples/dashboard
RUN mix deps.get --only prod && mix compile && mix release

FROM debian:bookworm-20240701-slim AS runner

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 HOME=/app
WORKDIR /app
COPY --from=builder /src/examples/dashboard/_build/prod/rel/virtuoso_dashboard ./

CMD ["/app/bin/virtuoso_dashboard", "start"]
```

Create `examples/dashboard/fly.toml`:

```toml
# Deploy FROM THE REPO ROOT (the Dockerfile needs the path dep in context):
#   fly deploy . -c examples/dashboard/fly.toml
app = "virtuoso-showcase"
primary_region = "iad"

[build]
  dockerfile = "examples/dashboard/Dockerfile"

[env]
  PHX_HOST = "virtuoso-showcase.fly.dev"
  PORT = "8080"

[deploy]
  release_command = "/app/bin/virtuoso_dashboard eval VirtuosoDashboard.Release.migrate"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0

[[vm]]
  size = "shared-cpu-1x"
  memory = "512mb"
```

- [x] **Step 4: README**

Rewrite the "Run it" section of `examples/dashboard/README.md` to cover: the
app is now the chat showcase (`/` chat, `/dashboard` ops); local run
unchanged; a new "## Deploy (Fly.io)" section:

```markdown
## Deploy (Fly.io)

One-time, from the **repo root**:

```sh
fly launch --no-deploy -c examples/dashboard/fly.toml   # accept/adjust app name
fly postgres create                                      # then: fly postgres attach
fly secrets set -c examples/dashboard/fly.toml \
  SECRET_KEY_BASE=$(openssl rand -hex 48) \
  ANTHROPIC_API_KEY=sk-ant-... \
  DASHBOARD_PASSWORD=...
fly deploy . -c examples/dashboard/fly.toml
```

Spend is bounded by `BUDGET_GLOBAL_DAILY` (default 500k tokens/day) and
`BUDGET_PER_CONVERSATION_DAILY` (default 10k) — the framework's Budget refuses
politely past the caps. Kill switch: `fly ssh console` →
`bin/virtuoso_dashboard rpc "Virtuoso.Budget.kill_switch(true)"`.
```

- [x] **Step 5: Verify prod compile + full local suites**

Run: `cd examples/dashboard && MIX_ENV=prod mix deps.get && MIX_ENV=prod mix compile --warnings-as-errors`
Expected: clean compile (runtime.exs is not evaluated at compile time, so no
secrets needed).

Run: `cd examples/dashboard && export PGUSER=justuseapen PGPASSWORD="" && mix test && mix format --check-formatted`
Expected: PASS.

Do NOT run `fly launch`/`fly deploy` — deployment is user-gated (outward
action; needs the user's Fly account and secrets).

- [x] **Step 6: Commit**

```bash
git add examples/dashboard
git commit -m "feat(showcase): Fly.io deployment — runtime config, release migrator, basic auth, Dockerfile"
```

---

### Task 7: Gates, docs, PR

**Files:**
- Modify: `docs/plans/2026-07-22-chat-showcase-plan.md` (check off tasks)

- [x] **Step 1: Root gates**

Run from repo root:
`export PGUSER=justuseapen PGPASSWORD="" && mix format --check-formatted && mix compile --warnings-as-errors && mix test && mix credo --strict && mix dialyzer`
Expected: all clean (the framework changed in Tasks 1–2).

- [x] **Step 2: Dashboard gates**

Run: `cd examples/dashboard && export PGUSER=justuseapen PGPASSWORD="" && mix format --check-formatted && mix compile --warnings-as-errors && mix test`
Expected: all clean.

- [x] **Step 3: Screenshot for the PR**

Boot `cd examples/dashboard && mix run --no-halt`, capture the chat + panel
after a couple of messages (agent-browser or the Chrome tools), upload per the
imgup skill, kill the server.

- [ ] **Step 4: Push + PR**

```bash
git push -u origin showcase/chat-demo
gh pr create --title "Chat showcase: ChatGPT-like demo with live ensemble engine panel" --body "…"
```

PR body: summary (spec link, framework `:telemetry_meta` addition, bot,
ChatLive, deploy artifacts), testing notes (both suites + gates), screenshot,
and Post-Deploy Monitoring section: watch `[:virtuoso, :ensemble, :run, :stop]`
volume + `Budget.global_spent/0` after any Fly deploy; failure signal = spend
approaching `BUDGET_GLOBAL_DAILY` unexpectedly fast → engage kill switch;
rollback = `fly deploy` previous image. Merge only after CI is green and the
user approves. Actual `fly launch`/`fly deploy` happens with the user.
```
