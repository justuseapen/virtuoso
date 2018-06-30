defmodule Mix.Tasks.Virtuoso.Gen.Routine do
  @moduledoc """
  Generates a basic routine for a given Bot.

    mix virtuoso.gen.bot BotName RoutineName

  The first argument is the bot's module name (BotName).

  The second argument is the desired routine module name (RoutineName)

  Generates `project/lib/bot/routine/new_routine.ex`
  """
  use Mix.Task

  def run(args) do
    [bot_module_name | [routine_module_name]] = args

    routine_file_path =
      routine_module_name
      |> Macro.underscore
      |> String.replace_suffix("", ".ex")
      |> String.replace_prefix("", "routine/")
      |> String.replace_prefix("", bot_directory(bot_module_name))

    template = bot_module_name |> routine_template(routine_module_name)
    Mix.Generator.create_file(routine_file_path, template)
  end

  @doc """
  Given a module name, returns the full path of the bot.
  """
  def bot_directory(bot_module_name) do
    bot_module_name
    |> Macro.underscore
    |> String.replace_suffix("", "/")
    |> String.replace_prefix("", "lib/")
  end

  @doc """
  Given a BotName and RoutineName return a routine template string
  """
  def routine_template(bot_module_name, routine_module_name) do
    bot_name =
      bot_module_name
      |> String.replace("_", " ")

    routine_name =
      bot_module_name
      |> String.replace("_", " ")

    """
    defmodule #{bot_module_name}.Routine.#{routine_module_name} do
      @moduledoc \"""
      #{bot_name}'s #{routine_name} routine.
      \"""

      def run() do
        "Yo."
      end
    end
    """
  end
end
