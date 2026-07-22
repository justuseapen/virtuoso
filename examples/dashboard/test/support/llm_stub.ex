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
