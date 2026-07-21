defmodule Virtuoso.EnsembleTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Ensemble
  alias Virtuoso.Ensemble.Strategy.Majority
  alias Virtuoso.LLM.Error

  # A member is a request variant; the test's llm fn maps model → a scripted
  # completion, so fan-out is deterministic without the process-scoped Mock.
  defp members(models) do
    Enum.map(models, fn m -> %{model: m} end)
  end

  defp completion(text),
    do: %{text: text, model: "m", stop_reason: :end_turn, usage: %{}, raw: %{}}

  # llm fn: model → {:ok, completion} | {:error, %Error{}}
  defp llm_returning(map) do
    fn request, _opts ->
      case Map.fetch(map, request.model) do
        {:ok, {:error, %Error{}} = err} -> err
        {:ok, text} -> {:ok, completion(text)}
        :error -> {:ok, completion("default")}
      end
    end
  end

  @base %{messages: [%{role: :user, content: "route this"}]}
  # extract: pull the structured decision from the completion text (here, identity)
  defp extract, do: fn %{text: text} -> {:ok, text} end

  describe "run/3 — happy path" do
    test "reaches majority consensus across members" do
      opts = [
        members: members(["a", "b", "c"]),
        strategy: Majority,
        extract: extract(),
        llm: llm_returning(%{"a" => "route_x", "b" => "route_x", "c" => "route_y"})
      ]

      assert {:consensus, "route_x", meta} = Ensemble.run(@base, opts)
      assert meta.count == 2
      assert meta.members_ok == 3
    end
  end

  describe "run/3 — partial failure" do
    test "drops members that error (429/timeout) and votes among survivors" do
      opts = [
        members: members(["a", "b", "c"]),
        strategy: Majority,
        extract: extract(),
        llm:
          llm_returning(%{
            "a" => "route_x",
            "b" => "route_x",
            "c" => {:error, Error.from_status(429, %{})}
          })
      ]

      assert {:consensus, "route_x", meta} = Ensemble.run(@base, opts)
      assert meta.members_ok == 2
      assert meta.members_dropped == 1
    end

    test "drops members whose extraction fails" do
      extract = fn %{text: text} -> if text == "bad", do: :error, else: {:ok, text} end

      opts = [
        members: members(["a", "b", "c"]),
        strategy: Majority,
        extract: extract,
        llm: llm_returning(%{"a" => "route_x", "b" => "route_x", "c" => "bad"})
      ]

      assert {:consensus, "route_x", meta} = Ensemble.run(@base, opts)
      assert meta.members_dropped == 1
    end
  end

  describe "run/3 — fallback" do
    test "falls back to a single model when consensus fails" do
      # a/b/c all disagree → no majority → single-model fallback uses the first survivor
      opts = [
        members: members(["a", "b", "c"]),
        strategy: Majority,
        extract: extract(),
        llm: llm_returning(%{"a" => "route_x", "b" => "route_y", "c" => "route_z"})
      ]

      assert {:fallback, decision, meta} = Ensemble.run(@base, opts)
      assert decision in ["route_x", "route_y", "route_z"]
      assert meta.reason == :no_majority or meta.reason == :tie
    end

    test "falls back when every member fails (below quorum)" do
      opts = [
        members: members(["a", "b"]),
        strategy: Majority,
        extract: extract(),
        llm:
          llm_returning(%{
            "a" => {:error, Error.timeout()},
            "b" => {:error, Error.from_status(529, %{})}
          })
      ]

      assert {:error, :all_members_failed, meta} = Ensemble.run(@base, opts)
      assert meta.members_ok == 0
    end
  end

  describe "run/3 — usage + telemetry (the dashboard's feed)" do
    defp attach(event) do
      ref = make_ref()
      parent = self()
      handler = "ens-test-#{inspect(ref)}"

      :telemetry.attach(
        handler,
        event,
        fn name, meas, meta, _ -> send(parent, {:telemetry, name, meas, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)
    end

    defp usage_completion(text, input, output) do
      %{
        text: text,
        model: "m",
        stop_reason: :end_turn,
        usage: %{input_tokens: input, output_tokens: output},
        raw: %{}
      }
    end

    test "meta aggregates token usage across members (cost per decision)" do
      llm = fn _r, _o -> {:ok, usage_completion("route_x", 10, 5)} end

      opts = [members: members(["a", "b", "c"]), strategy: Majority, extract: extract(), llm: llm]

      assert {:consensus, "route_x", meta} = Ensemble.run(@base, opts)
      assert meta.usage == %{input_tokens: 30, output_tokens: 15}
    end

    test "emits start and stop telemetry with outcome, votes, dissent, and usage" do
      attach([:virtuoso, :ensemble, :run, :start])
      attach([:virtuoso, :ensemble, :run, :stop])

      llm = fn req, _o ->
        text = if req.model == "c", do: "route_y", else: "route_x"
        {:ok, usage_completion(text, 10, 5)}
      end

      opts = [members: members(["a", "b", "c"]), strategy: Majority, extract: extract(), llm: llm]
      assert {:consensus, "route_x", _} = Ensemble.run(@base, opts)

      assert_received {:telemetry, [:virtuoso, :ensemble, :run, :start], start_meas, start_meta}
      assert is_integer(start_meas.system_time)
      assert start_meta.members_total == 3
      assert start_meta.strategy == Majority

      assert_received {:telemetry, [:virtuoso, :ensemble, :run, :stop], stop_meas, stop_meta}
      assert is_integer(stop_meas.duration)
      assert stop_meta.outcome == :consensus
      assert stop_meta.decision == "route_x"
      # 2 of 3 agreed — one dissenter
      assert stop_meta.count == 2
      assert stop_meta.members_ok == 3
      assert stop_meta.usage == %{input_tokens: 30, output_tokens: 15}
    end

    test "stop telemetry reports fallback and error outcomes" do
      attach([:virtuoso, :ensemble, :run, :stop])

      # all disagree → fallback
      llm = fn req, _o -> {:ok, usage_completion("route_#{req.model}", 1, 1)} end
      opts = [members: members(["a", "b", "c"]), strategy: Majority, extract: extract(), llm: llm]
      assert {:fallback, _, _} = Ensemble.run(@base, opts)
      assert_received {:telemetry, _, _, %{outcome: :fallback}}

      # all fail → error
      err_llm = fn _r, _o -> {:error, Error.timeout()} end
      opts = [members: members(["a", "b"]), strategy: Majority, extract: extract(), llm: err_llm]
      assert {:error, :all_members_failed, _} = Ensemble.run(@base, opts)
      assert_received {:telemetry, _, _, %{outcome: :error}}
    end
  end

  describe "run/3 — purity" do
    test "members receive their model variant merged onto the base request" do
      parent = self()

      capturing = fn request, _opts ->
        send(parent, {:member_request, request.model, request.messages})
        {:ok, completion("route_x")}
      end

      opts = [
        members: [%{model: "a", temperature: 0.0}, %{model: "b", temperature: 1.0}],
        strategy: Majority,
        extract: extract(),
        llm: capturing
      ]

      Ensemble.run(@base, opts)

      assert_received {:member_request, "a", [%{content: "route this"}]}
      assert_received {:member_request, "b", [%{content: "route this"}]}
    end
  end
end
