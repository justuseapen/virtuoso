defmodule VirtuosoDashboard.Bot.Routines.AboutVirtuoso do
  @moduledoc "Answers questions about the framework — the \"about_virtuoso\" route."

  @behaviour Virtuoso.Routine

  alias VirtuosoDashboard.Bot.Generate

  @prompt_path "priv/prompts/showcase/about.md"
  @external_resource @prompt_path
  @prompt File.read!(@prompt_path)

  @impl true
  def run(impression, context), do: Generate.reply(impression, context, @prompt)
end
