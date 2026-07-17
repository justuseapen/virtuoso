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
