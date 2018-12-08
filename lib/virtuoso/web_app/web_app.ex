defmodule Virtuoso.WebApp do
  @moduledoc """
  Translates WebApp post message events into Virtuoso-friendly internal representations (Impressions)
  """

  alias Virtuoso.WebApp.Message

  @doc """
  Entry point for regular messages (free text)
  """
  def process_messages(entries) do
    entries
    |> Message.received_message
  end
end
