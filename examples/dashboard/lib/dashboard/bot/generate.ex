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
    # Single source of truth for models/limits: config.exs (env-overridable in
    # prod via runtime.exs). fetch! so a missing key fails loudly at call time.
    chat = Application.fetch_env!(:virtuoso_dashboard, :chat)

    request = %{
      model: Keyword.fetch!(chat, :generation_model),
      system: system,
      max_tokens: Keyword.fetch!(chat, :max_tokens),
      messages: history_messages(context) ++ [%{role: :user, content: imp.text || ""}]
    }

    case Budget.with_budget(imp.conversation_id, fn -> LLM.complete(request) end) do
      {:ok, %{text: text}} -> {:reply, text}
      {:refused, _reason, refusal} -> {:reply, refusal}
      {:error, _error} -> {:reply, @error_reply}
    end
  end

  # History roles are always :user | :assistant atoms — live entries are pushed
  # as atoms and log rehydration goes through an Ecto.Enum field.
  defp history_messages(context) do
    context
    |> Map.get(:history, [])
    |> Enum.filter(fn {_role, content} -> is_binary(content) end)
    |> Enum.take(-@history_window)
    |> Enum.map(fn {role, content} -> %{role: role, content: content} end)
  end
end
