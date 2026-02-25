defmodule Virtuoso.Agent.LLM.OpenAITest do
  use ExUnit.Case

  alias Virtuoso.Agent.LLM.OpenAI

  test "returns error when API key is missing" do
    original = Application.get_env(:virtuoso, :openai_api_key)
    Application.delete_env(:virtuoso, :openai_api_key)

    System.delete_env("OPENAI_API_KEY")

    messages = [%{role: "user", content: "Hello"}]
    result = OpenAI.chat(messages, [], [])

    assert {:error, :missing_api_key} = result

    if original, do: Application.put_env(:virtuoso, :openai_api_key, original)
  end
end
