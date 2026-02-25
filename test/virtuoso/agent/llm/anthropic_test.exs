defmodule Virtuoso.Agent.LLM.AnthropicTest do
  use ExUnit.Case

  alias Virtuoso.Agent.LLM.Anthropic

  test "returns error when API key is missing" do
    # Ensure no API key is set
    original = Application.get_env(:virtuoso, :anthropic_api_key)
    Application.delete_env(:virtuoso, :anthropic_api_key)

    # Also clear env var for this test
    System.delete_env("ANTHROPIC_API_KEY")

    messages = [%{role: "user", content: "Hello"}]
    result = Anthropic.chat(messages, [], [])

    assert {:error, :missing_api_key} = result

    # Restore
    if original, do: Application.put_env(:virtuoso, :anthropic_api_key, original)
  end
end
