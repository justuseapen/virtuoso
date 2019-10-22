defmodule MementoMori.Routine.Default do
  @moduledoc """
      MementoMori's Default routine.
  """
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
