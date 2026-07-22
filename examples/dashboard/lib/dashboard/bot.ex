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
