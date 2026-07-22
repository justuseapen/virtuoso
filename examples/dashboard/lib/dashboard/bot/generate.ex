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
