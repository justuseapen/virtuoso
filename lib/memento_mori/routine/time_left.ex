defmodule MementoMori.Routine.TimeLeft do
  @moduledoc """
  How much time do you have left?
  """

  @frame {
    {:age, 0},
    {:birth_year, 2018}
  }

  def run(impression) do
    # Get age from impression
    age = 25
    # Lookup life remaining from Actuarial Life Table
    "You have 52 years left to live"
  end
end
