defmodule Mix.Tasks.Virtuoso.Gen.Bot do
  @moduledoc """
  Generates executive, routines, and cognition for a Bot.

    mix virtuoso.gen.bot BotModuleName

  The first argument is the bot's name
  """
  use Mix.Task
  alias Mix.Generator
  alias Virtuoso.Bot
  alias Virtuoso.Utilities.Util

  def run(args) do
    [bot_module_name | _] = args

    bot_module_name
    |> generate_bot_directories
    |> generate_routine_interface
    |> generate_default_routine()
    |> generate_bot_entries()
    |> generate_cognition_layers
  end

  def generate_bot_directories(bot_module_name) do
    bot_module_name
    |> _generate_bot_directory
    |> _generate_bot_interface
    |> create_routine_directory
    |> create_slow_thinking_directory
  end

  def _generate_bot_directory(bot_module_name) do
    with true <-
           bot_module_name
           |> Bot.bot_directory_path()
           |> Generator.create_directory() do
      bot_module_name
    end
  end

  def _generate_bot_interface(bot_module_name) do
    with true <-
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

    bot_module_name
    |> Bot.bot_directory_path()
    |> String.replace_suffix("", "slow_thinking.ex")
    |> Generator.create_file(slow_thinking_template(bot_module_name))

    bot_module_name
    |> Bot.bot_directory_nlp_path()
    |> String.replace_suffix("", "wit.ex")
    |> Generator.create_file(slow_thinking_wit_template(bot_module_name))

    bot_module_name
    |> Bot.bot_directory_nlp_path()
    |> String.replace_suffix("", "watson.ex")
    |> Generator.create_file(slow_thinking_watson_template(bot_module_name))
  end

  def generate_routine_interface(bot_module_name) do
    with true <-
           bot_module_name
           |> Bot.bot_directory_path()
           |> String.replace_suffix("", "routine.ex")
           |> Generator.create_file(routine_template(bot_module_name)) do
      bot_module_name
    end
  end

  def create_routine_directory(bot_module_name) do
    with true <-
           bot_module_name
           |> Bot.bot_directory_path()
           |> String.replace_suffix("", "routine")
           |> Generator.create_directory() do
      bot_module_name
    end
  end

  def create_slow_thinking_directory(bot_module_name) do
    with true <-
           bot_module_name
           |> Bot.bot_directory_path()
           |> String.replace_suffix("", "slow_thinking")
           |> Generator.create_directory() do
      bot_module_name
    end
  end

  def generate_default_routine(bot_module_name) do
    routine_file_path =
      "Default"
      |> Macro.underscore()
      |> String.replace_suffix("", ".ex")
      |> String.replace_prefix("", "routine/")
      |> String.replace_prefix("", Bot.bot_directory_path(bot_module_name))

    template = default_routine_template(bot_module_name)

    with true <-
           Generator.create_file(routine_file_path, template) do
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
      alias #{bot_module_name}.SlowThinking
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

  def slow_thinking_template(bot_module_name) do
    """
    defmodule #{bot_module_name}.SlowThinking do
      @moduledoc \"""
      If FastThinking failed to deduce entities and intents then SlowThinking may use a Virtuoso NLP client to determine which routine the bot should execute.
      \"""

      @default_nlp Application.get_env(:virtuoso, :default_nlp)

      def run(impression) when is_nil(@default_nlp) do
        impression
      end

      def run(%{intent: intent} = impression) when not(is_nil(intent)) do
        impression
      end

      def run(impression) do
        impression
        |> module_thinking().run
      end

      def module_thinking do
        Module.concat(["#{bot_module_name}","SlowThinking",@default_nlp])
      end

      defp nlp do
        @default_nlp
        |> Atom.to_string
        |> Macro.camelize
      end
    end
    """
  end

  def slow_thinking_wit_template(bot_module_name) do
    """
    defmodule #{bot_module_name}.SlowThinking.Wit do
      @moduledoc \"""
      If FastThinking failed to deduce entities and intents then SlowThinking may use a Virtuoso NLP client to determine which routine the bot should execute.
      \"""

      def run(impression) do
        impression
        |> maybe_get_entities
        |> maybe_get_intents
      end

      def maybe_get_entities(%{intent: _intent} = impression), do: impression
      # message is nil when the incoming message is an image
      def maybe_get_entities(%{message: nil} = impression), do: impression
      def maybe_get_entities(%{message: message} = impression) do
        with {:ok, response} <- Wit.Agent.get(message) do
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

      defp get_most_likely_intent(%{entities: %{"intent" => [%{"value" => intent}|_t]}} = impression) do
        impression
        |> Map.merge(%{intent: intent})
      end
      defp get_most_likely_intent(impression) do
        impression
      end
    end
    """
  end

  def slow_thinking_watson_template(bot_module_name) do
    """
    defmodule #{bot_module_name}.SlowThinking.Watson do
      @moduledoc \"""
      If FastThinking failed to deduce entities and intents then SlowThinking may use a Virtuoso NLP client to determine which routine the bot should execute.
      \"""

      def run(impression) do
        impression
        |> get_conversation_session
        |> think_and_answer
      end

      defp get_conversation_session(%{sender_id: sender_id} = impression) do
        with state = Virtuoso.Conversation.get_session(sender_id) do
          with %{session_id: session_id} = state do
            session_id
            |> (&Map.merge(impression, %{session_id: &1})).()
          end
        end
      end

      defp think_and_answer(%{message: message, session_id: session_id} = impression) do
        with {:ok, response} <- Watson.Agent.think_and_answer(session_id, message) do
          response
          |> get_output(impression)
          |> get_context(response)
        end
      end

      defp get_output(%{output: %{generic: responses, entities: entities, intents: intents}} = response, impression) do
        impression
        |> add_responses(responses)
        |> add_intents(intents)
        |> add_entities(entities)
      end

      defp get_context(impression, %{context: %{skills: %{"main skill": %{user_defined: context}}}} = response) do
        impression
        |> add_context(context)
      end
      defp get_context(impression, _) do
        impression
      end

      defp add_context(impression, user_defined) do
        user_defined
        |> (&Map.merge(impression, %{context: &1})).()
      end

      defp add_responses(impression, responses) do
        responses
        |> (&Map.merge(impression, %{responses: &1})).()
      end

      defp add_intents(impression, intents) do
        intents
        |> (&Map.merge(impression, %{intents: &1})).()
      end

      defp add_entities(impression, entities) do
        entities
        |> (&Map.merge(impression, %{entities: &1})).()
      end

      defp get_session(%{body: watson_response}) do
        watson_response
        |> Poison.decode!
        |> Map.fetch!("session_id")
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
      @default_routine Application.get_env(:#{Macro.underscore(bot_module_name)}, :default_routine) || #{
      bot_module_name
    }.Routine.Default

      @doc \"""
      Initiates a routine given a corresponding intent string.
      Intent string gets converted into corresponding routine module name
      and calls run function in routine module dynamically.
      \"""
      def runner(%{responses: responses} = impression, _conversation_state) when not(is_nil(responses)) do
        responses
        |> send_messenger
      end
      def runner(%{intent: intent} = impression, _conversation_state) when not(is_nil(intent)) do
        intent
        |> Macro.camelize()
        |> String.replace_prefix("", @module_name_expanded)
        |> String.to_existing_atom()
        |> apply(:run, [impression])
      end
      def runner(impression, _conversation_state) do
        @default_routine.run(impression)
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

  def default_routine_template(bot_module_name) do
    """
    defmodule #{bot_module_name}.Routine.Default do
      @moduledoc \"""
      #{Bot.humanize(bot_module_name)}'s Default routine.
      \"""

      alias Virtuoso.Impression
      def run(%Impression{debug: debug} = impression) when debug == true do
        %{text: run(), impression: impression}
      end

      def run(%Impression{} = impression) do
        run()
      end    
      def run() do
        "So sorry, I didn't get it."
      end
    end
    """
  end

  @doc """
    Generate new entry in the map for every bot created.
  """
  def generate_bot_entries(bot_module_name) do
    with {:ok, content} <- Util.get_current_state(),
         {:ok, decoded_contents} <- Poison.decode(content),
         new_content =
           Util.atomic_map(decoded_contents)
           |> Map.put(bot_module_name, ["active", "user_created"]),
         {:ok, encoded_new_content} <- Poison.encode(new_content),
         true <- Generator.create_file("bot.lock", encoded_new_content, force: true) do
      bot_module_name
    else
      {:error, _reason} -> {:error, _reason}
    end
  end
end
