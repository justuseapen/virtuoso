defmodule VirtuosoDashboard.Bot.Routines.Answer do
  @moduledoc "General chat generation — the \"answer\" route."

  @behaviour Virtuoso.Routine

  alias VirtuosoDashboard.Bot.Generate

  @prompt_path "priv/prompts/showcase/answer.md"
  @external_resource @prompt_path
  @prompt File.read!(@prompt_path)

  @impl true
  def run(impression, context), do: Generate.reply(impression, context, @prompt)
end
