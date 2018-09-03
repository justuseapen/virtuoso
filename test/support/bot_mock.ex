defmodule BotMock do
  @moduledoc """
  """

  def recipient_ids do
    [
      "TEST_RECIPIENT"
    ]
  end

  def respond_to(_impression, _conversation_state) do
    'yo'
  end
end
