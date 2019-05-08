defmodule Mix.Tasks.Virtuoso.Gen.Bot do
  @moduledoc """
  Generates executive, routines, and cognition for a Bot.

    mix virtuoso.gen.bot BotModuleName

  The first argument is the bot's name
  """
  use Mix.Task
  alias Mix.Generator
  alias Virtuoso.Bot

  def run(args) do
    [bot_module_name | _] = args

    bot_module_name
    |> generate_bot_directories
    |> generate_routine_interface
    |> generate_cognition_layers
  end

  def generate_bot_directories(bot_module_name) do
    bot_module_name
    |> _generate_bot_directory
    |> _generate_bot_interface
    |> create_routine_directory
  end

  def _generate_bot_directory(bot_module_name) do
    with :ok <-
           bot_module_name
           |> Bot.bot_directory_path()
           |> Generator.create_directory() do
      bot_module_name
    end
  end

  def _generate_bot_interface(bot_module_name) do
    with :ok <-
           bot_module_name
           |> Macro.underscore()
           |> String.replace_prefix("", "#{File.cwd!()}/lib/")
           |> String.replace_suffix("", ".ex")
           |> Generator.create_file(bot_interface_template(bot_module_name)) do
      bot_module_name
    end
  end

  def generate_cognition_layers(bot_module_name) do
    bot_module_name
    |> Bot.bot_directory_path()
    |> String.replace_suffix("", "fast_thinking.ex")
    |> Generator.create_file(fast_thinking_template(bot_module_name))
  end

  def generate_routine_interface(bot_module_name) do
    with :ok <-
           bot_module_name
           |> Bot.bot_directory_path()
           |> String.replace_suffix("", "routine.ex")
           |> Generator.create_file(routine_template(bot_module_name)) do
      bot_module_name
    end
  end

  def create_routine_directory(bot_module_name) do
    with :ok <-
           bot_module_name
           |> Bot.bot_directory_path()
           |> String.replace_suffix("", "routine")
           |> Generator.create_directory() do
      bot_module_name
    end
  end

  def bot_interface_template(bot_module_name) do
    """
    defmodule #{bot_module_name} do
      @moduledoc \"""
      Who is this bot?
      \"""
      alias #{bot_module_name}.FastThinking
      alias #{bot_module_name}.Routine

      @recipient_ids [
        Application.get_env(:#{Macro.underscore(bot_module_name)}, :fb_page_recipient_id)
      ]

      @tokens %{
        fb_page_access_token: Application.get_env(:#{Macro.underscore(bot_module_name)}, :fb_page_access_token)
      }

      @doc \"""
      Getter for receiver_ids
      \"""
      def recipient_ids(), do: @recipient_ids

      @doc \"""
      Gets token by client
      \"""
      def token(:fb), do: @tokens[:fb_page_access_token]

      @doc \"""
      Main pipeline for the bot.
      \"""
      def respond_to(impression, %{nlp: nlp} = conversation_state) do
        impression
        |> FastThinking.run()
        |> Virtuoso.Thinker.module_thinker_slow_thinking(nlp).run()
        |> Routine.runner(conversation_state)
      end
    end
    """
  end

  def fast_thinking_template(bot_module_name) do
    """
    defmodule #{bot_module_name}.FastThinking do
      @moduledoc \"""
      FastThinking checks for intents and entities expressly implied by the impression structure or contents.
      This allows us to bypass SlowThinking when it is performant to do so.
      \"""

      @doc \"""
      Add new function definitions, pattern matching against the impression in order to catch common user intents.
      def run(%{message: "Hello Bot"} = impression) do
        impression
        |> Map.merge(%{intent: "hello_world"})
      end
      \"""

      def run(impression), do: impression
    end
    """
  end

  def routine_template(bot_module_name) do
    """
    defmodule #{bot_module_name}.Routine do
      @moduledoc \"""
      Interface for all of #{Bot.humanize(bot_module_name)}'s routines.
      \"""

      @module_name_expanded  "Elixir.#{bot_module_name}.Routine."
      @default_routine Application.get_env(:#{Macro.underscore(bot_module_name)}, :default_routine)

      @doc \"""
      Initiates a routine given a corresponding intent string.
      Intent string gets converted into corresponding routine module name
      and calls run function in routine module dynamically.
      \"""
      def runner(%{responses: responses} = impression, _conversation_state) do
        responses
        |> send_messenger
      end
      def runner(%{intent: intent} = impression, _conversation_state) do
        intent
        |> Macro.camelize()
        |> String.replace_prefix("", @module_name_expanded)
        |> String.to_existing_atom()
        |> apply(:run, [impression])
      end
      def runner(_impression, _conversation_state) do
        @default_routine.run()
      end

      def send_messenger([response | t]) do
        response
      end
      def send_messenger(%{text: text} = response) do
        text
      end
    end
    """
  end
end
