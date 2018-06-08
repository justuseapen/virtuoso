defmodule Medium do
  @moduledoc"""
  Receives events and delegates to platform-specific module.
  """

  @doc """
  Accepts params and delegates based on incoming message structure
  """
  def handle(%{"object" => _object, "entry" => entries}) do
    Medium.FbMessenger.process_messages(entries)
  end
end
