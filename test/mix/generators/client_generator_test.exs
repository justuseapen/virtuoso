Code.require_file("../../support/mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Virtuoso.Gen.ClientTest do
  @moduledoc """
  Tests client generation
  """

  use ExUnit.Case
  import MixHelper
  alias Mix.Tasks.Virtuoso.Gen
  # Check if app_web/controllers exists
  # if yes, generate webhook controller
  # if no, throw error

  describe "run/2" do
    test "generates a fb client for an existing bot." do
      in_tmp('test', fn ->
        send(self(), {:mix_shell_input, :yes?, true})
        Gen.Client.run(["GraceKelly", "FbMessenger"])

        assert_file("lib/virtuoso_web/controllers/webhook_controller.ex", fn file ->
          assert file =~ """
                 def verify(conn, %{\"hub.mode\" => mode, \"hub.verify_token\" => token, \"hub.challenge\" => challenge}) do
                 """
        end)
      end)
    end
  end
end
