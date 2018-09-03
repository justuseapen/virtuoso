Code.require_file "../../support/mix_helper.exs", __DIR__

defmodule Mix.Tasks.Virtuoso.Gen.RoutineTest do
  @moduledoc """
  Tests generating a routine
  """

  use ExUnit.Case
  import MixHelper
  alias Mix.Tasks.Virtuoso.Gen

  describe "run/1" do
    test "generates a basic bot with a greeting routine." do
      in_tmp('test', fn ->
        Gen.Routine.run(["GraceKelly", "GraceQuotes"])
        assert_file "lib/grace_kelly/routine/grace_quotes.ex", fn file ->
          assert file =~ "defmodule GraceKelly.Routine.GraceQuotes do"
        end
      end)
    end
  end
end
