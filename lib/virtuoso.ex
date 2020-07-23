defmodule Virtuoso do
  @moduledoc """
  Virtuoso keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Accepts params and delegates based on incoming message structure
  """

  alias Virtuoso.{Message}

  def handle(%{"object" => object, "entry" => entry}) do
    process_messages(object, entry)
  end

  def process_messages(object, entry) do
    Message.received_message(entry["messaging"])
  end
end