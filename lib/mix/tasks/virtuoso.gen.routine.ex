defmodule Mix.Tasks.Virtuoso.Gen.Routine do
  @moduledoc """
  Generates a basic routine for a given Bot.

    mix virtuoso.gen.bot BotName RoutineName

  The first argument is the bot's module name (BotName).

  The second argument is the desired routine module name (RoutineName)

  Generates `project/lib/bot/routine/new_routine.ex`
  """
  use Mix.Task
  alias Virtuoso.Bot

  def run(args) do
    [bot_module_name | [routine_module_name]] = args

    routine_file_path =
      routine_module_name
      |> Macro.underscore()
      |> String.replace_suffix("", ".ex")
      |> String.replace_prefix("", "routine/")
      |> String.replace_prefix("", Bot.bot_directory_path(bot_module_name))

    template = bot_module_name |> routine_template(routine_module_name)
    Mix.Generator.create_file(routine_file_path, template)
  end

  @doc """
  Given a BotName and RoutineName return a routine template string
  """
  def routine_template(bot_module_name, routine_module_name) do
    bot_name = Bot.humanize(bot_module_name)

    routine_name = Bot.humanize(routine_module_name)

    """
    defmodule #{bot_module_name}.Routine.#{routine_module_name} do
      @moduledoc \"""
      #{bot_name}'s #{routine_name} routine.
      \"""

      alias Virtuoso.Impression

      def run(%Impression{debug: debug} = impression) when debug == true do
        %{text: run(), impression: impression}
      end

      def run(%Impression{} = impression) do
        run()
      end

      def run() do
        "Yo"
      end
    end
    """
  end
end
