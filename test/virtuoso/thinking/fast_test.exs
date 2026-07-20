defmodule Virtuoso.Thinking.FastTest do
  use ExUnit.Case, async: true

  alias Virtuoso.Impression
  alias Virtuoso.Thinking.Fast

  defmodule Greeter do
    @behaviour Virtuoso.Thinking.Fast
    @impl true
    def match(%Impression{text: text}, _ctx) do
      if String.downcase(text || "") in ["hi", "hello", "hey"] do
        {:match, {:reply, "Hello!"}}
      else
        :no_match
      end
    end
  end

  defmodule Stopper do
    @behaviour Virtuoso.Thinking.Fast
    @impl true
    def match(%Impression{text: "stop"}, _ctx), do: {:match, :noreply}
    def match(_imp, _ctx), do: :no_match
  end

  defp imp(text) do
    Impression.new(
      channel: :web_chat,
      conversation_id: "c",
      sender_id: "s",
      message_id: "m",
      text: text
    )
  end

  describe "run/3" do
    test "returns the first matching fast-thinker's decision" do
      assert {:match, {:reply, "Hello!"}} = Fast.run([Greeter, Stopper], imp("hi"), %{})
    end

    test "tries matchers in order and returns the first match" do
      assert {:match, :noreply} = Fast.run([Greeter, Stopper], imp("stop"), %{})
    end

    test "returns :no_match when nothing matches (→ falls through to SlowThinking)" do
      assert :no_match = Fast.run([Greeter, Stopper], imp("what's the weather"), %{})
    end

    test "an empty matcher list is always :no_match" do
      assert :no_match = Fast.run([], imp("hi"), %{})
    end
  end
end
