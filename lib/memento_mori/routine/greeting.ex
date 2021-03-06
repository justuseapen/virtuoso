defmodule MementoMori.Routine.Greeting do
  @moduledoc """
  Memento Mori's greeting routine.
  """
  alias Virtuoso.Impression

  def run(%Impression{debug: debug} = impression) when debug == true do
    %{text: run(), impression: impression}
  end

  def run(%Impression{} = impression) do
    run()
  end

  def run() do
    "Hey"
  end
end
