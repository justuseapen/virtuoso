defmodule Virtuoso.BotTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Ensemble.Strategy.{Judge, Majority}
  alias Virtuoso.Impression

  defmodule Greeter do
    @behaviour Virtuoso.Thinking.Fast
    @impl true
    def match(%Impression{text: t}, _),
      do: if(t == "hi", do: {:match, {:reply, "Hey!"}}, else: :no_match)
  end

  defmodule BookRoutine do
    @behaviour Virtuoso.Routine
    @impl true
    def run(%Impression{}, _), do: {:reply, "Booked."}
  end

  defmodule ExtractRoutine do
    @behaviour Virtuoso.Routine
    @impl true
    def run(%Impression{}, _), do: {:reply, "Extracted."}
  end

  defmodule DemoBot do
    use Virtuoso.Bot

    @impl true
    def fast, do: [Greeter]

    @impl true
    def ensemble, do: [n: 3, strategy: :majority]

    @impl true
    def routines do
      %{
        "book" => BookRoutine,
        # per-routine override: extraction wants a bigger judged ensemble
        "extract" => {ExtractRoutine, ensemble: [n: 5, strategy: :judge]}
      }
    end
  end

  defp imp(text) do
    Impression.new(
      channel: :web_chat,
      conversation_id: "c",
      sender_id: "s",
      message_id: "m-#{System.unique_integer([:positive])}",
      text: text
    )
  end

  defp vote(route) do
    fn _r, _o ->
      {:ok, %{text: route, model: "m", stop_reason: :end_turn, usage: %{}, raw: %{}}}
    end
  end

  describe "bot definition" do
    test "exposes its declared config" do
      assert DemoBot.fast() == [Greeter]
      assert DemoBot.ensemble() == [n: 3, strategy: :majority]
      assert Map.has_key?(DemoBot.routines(), "book")
    end

    test "routine_registry/0 strips overrides to a plain name→module map" do
      reg = DemoBot.routine_registry()
      assert reg["book"] == BookRoutine
      assert reg["extract"] == ExtractRoutine
    end

    test "ensemble_for/1 merges per-routine overrides onto bot defaults" do
      # book has no override → bot default
      book = DemoBot.ensemble_for("book")
      assert book.n == 3
      assert book.strategy == Majority

      # extract overrides n and strategy
      extract = DemoBot.ensemble_for("extract")
      assert extract.n == 5
      assert extract.strategy == Judge
    end
  end

  describe "responder/1" do
    test "FastThinking answers a greeting" do
      assert {:reply, "Hey!"} = DemoBot.responder(llm: vote("book")).(imp("hi"), [])
    end

    test "SlowThinking routes via the bot's ensemble config" do
      assert {:reply, "Booked."} =
               DemoBot.responder(llm: vote("book")).(imp("book me a table"), [])
    end
  end

  test "DemoBot implements Virtuoso.Bot" do
    behaviours = DemoBot.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()
    assert Virtuoso.Bot in behaviours
  end
end
