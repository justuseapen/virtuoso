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
    [bot_module_name|_] = args

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
   with :ok <- bot_module_name
    |> Bot.bot_directory_path
    |> Generator.create_directory do
      bot_module_name
    end
  end

  def _generate_bot_interface(bot_module_name) do
    with :ok <- bot_module_name
    |> Macro.underscore
    |> String.replace_prefix("", "#{File.cwd!}/lib/")
    |> String.replace_suffix("", ".ex")
    |> Generator.create_file(bot_interface_template(bot_module_name)) do
      bot_module_name
    end
  end

  def generate_cognition_layers(bot_module_name) do
    bot_module_name
    |> Bot.bot_directory_path
    |> String.replace_suffix("", "fast_thinking.ex")
    |> Generator.create_file(fast_thinking_template(bot_module_name))

    bot_module_name
    |> Bot.bot_directory_path
    |> String.replace_suffix("", "slow_thinking.ex")
    |> Generator.create_file(slow_thinking_template(bot_module_name))
  end

  def generate_routine_interface(bot_module_name) do
    with :ok <- bot_module_name
    |> Bot.bot_directory_path
    |> String.replace_suffix("", "routine.ex")
    |> Generator.create_file(routine_template(bot_module_name)) do
      bot_module_name
    end
  end

  def create_routine_directory(bot_module_name) do
    with :ok <- bot_module_name
    |> Bot.bot_directory_path
    |> String.replace_suffix("", "routine")
    |> Generator.create_directory do
      bot_module_name
    end
  end

  def bot_interface_template(bot_module_name) do
    bot_dir = bot_module_name |> Macro.underscore
    """
    defmodule #{bot_module_name} do
      @moduledoc \"""
      Who is this bot?
      \"""
      alias #{bot_module_name}.FastThinking
      alias #{bot_module_name}.SlowThinking
      alias #{bot_module_name}.Routine

      @recipient_ids [
        Application.get_env(:#{bot_dir}, :fb_page_recipient_id)
      ]

      @tokens %{
        fb_page_access_token: Application.get_env(:#{bot_dir}, :fb_page_access_token)
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
      def respond_to(impression, conversation_state) do
        impression
        |> FastThinking.run()
        |> SlowThinking.run()
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

      def run(impression), do: impression
    end
    """
  end

  def slow_thinking_template(bot_module_name) do
    """
    defmodule #{bot_module_name}.SlowThinking do
      @moduledoc \"""
      If FastThinking failed to deduce entities and intents then SlowThinking may use a Virtuoso NLP client to determine which routine the bot should execute.
      \"""

      @nlp Wit.Client

      def run(impression) do
        impression
        |> maybe_get_entities
        |> maybe_get_intents
      end

      def maybe_get_entities(%{intent: _intent} = impression), do: impression
      def maybe_get_entities(%{message: message} = impression) do
        with {:ok, response} <- @nlp.get(message) do
          response
          |> gets_entities
          |> (&Map.merge(impression, %{entities: &1})).()
        end
      end

      defp gets_entities(%{body: wit_response}) do
        wit_response
        |> Poison.decode!()
        |> Map.fetch("entities")
        |> elem(1)
      end

      def maybe_get_intents(impression) do
        impression
        |> get_most_likely_intent()
        |> Map.merge(impression)
      end

      defp get_most_likely_intent(impression) do
        impression
      end
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
      def runner(%{intent: intent} = impression, _conversation_state) do
        intent
        |> String.replace(" ", "")
        |> Macro.camelize
        |> String.replace_prefix("", @module_name_expanded)
        |> String.to_existing_atom
        |> apply(:run, impression)
      end
      def runner(_impression, _conversation_state) do
        @default_routine.run()
      end
    end
    """
  end
end
