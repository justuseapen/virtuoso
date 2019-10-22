defmodule Virtuoso.Bot do
  @moduledoc """
  External Interface for Bot context
  """

  alias Virtuoso.Bot.Map
  alias Virtuoso.Utilities.Util

  def get(recipient_id) do
    Map.bots()
    |> Enum.find(fn bot -> bot == recipient_id end)
    |> Util.get_bot_module()
  end

  @doc """
  Returns token by recipient id
  """
  def get_token_by_recipient_id(id, client) do
    bot =
      id
      |> get

    bot.token(client)
  end

  def handles_message(bot, impression, conversation_state) do
    impression
    |> bot.respond_to(conversation_state)
  end

  @doc """
  Given a module name, returns the full path of the bot.
  """
  def bot_directory_path(bot_module_name) do
    bot_module_name
    |> Macro.underscore()
    |> String.replace_suffix("", "/")
    |> String.replace_prefix("", "lib/")
  end

  @doc """
  Given a module name, returns the full path of the bot.
  """
  def bot_directory_nlp_path(bot_module_name) do
    bot_module_name
    |> Macro.underscore()
    |> String.replace_suffix("", "/slow_thinking/")
    |> String.replace_prefix("", "lib/")
  end

  @doc """
  Takes a bot's module name and humanizes it
  """
  def humanize(module_name) do
    module_name |> String.replace("_", " ")
  end
end
