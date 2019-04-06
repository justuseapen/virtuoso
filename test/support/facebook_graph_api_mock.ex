defmodule Virtuoso.FacebookGraphApi.HttpMock do
  @moduledoc """
  """
  def send_messenger_response(_response), do: :ok
  def send_messenger_response(_response, _token), do: :ok
end
