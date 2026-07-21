defmodule Mix.Tasks.Virtuoso.GenTest do
  # File.cd! mutates the process-global cwd, so these can't run alongside others.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Virtuoso.Gen.{Bot, Routine, Tool}
  alias Virtuoso.Impression

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    tmp =
      Path.join(System.tmp_dir!(), "virtuoso_gen_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, tmp: tmp}
  end

  defp in_tmp(tmp, fun), do: File.cd!(tmp, fun)

  # Drain every {:mix_shell, :info, _} message (create_file logs each file, then
  # the task prints its next-steps hint) and return them all.
  defp shell_infos(acc \\ []) do
    receive do
      {:mix_shell, :info, [msg]} -> shell_infos([msg | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # Compile a generated file in the tmp project and register cleanup so the
  # modules don't leak into other tests.
  defp compile!(path) do
    modules = Code.compile_string(File.read!(path), path)

    on_exit(fn ->
      for {mod, _bin} <- modules do
        :code.purge(mod)
        :code.delete(mod)
      end
    end)

    modules
  end

  describe "mix virtuoso.gen.bot" do
    test "generates a bot that compiles and chats via FastThinking", %{tmp: tmp} do
      in_tmp(tmp, fn ->
        Bot.run(["Demo"])

        assert File.exists?("lib/demo/bot.ex")
        assert File.exists?("lib/demo/fast/greeting.ex")
        assert File.exists?("lib/demo/routines/echo.ex")
        assert File.exists?("priv/prompts/demo/router.md")

        # Dependency order: matcher + routine first, then the bot (which
        # references them and embeds the prompt file relative to cwd).
        compile!("lib/demo/fast/greeting.ex")
        compile!("lib/demo/routines/echo.ex")
        compile!("lib/demo/bot.ex")

        imp =
          Impression.new(
            channel: :test,
            conversation_id: "c1",
            sender_id: "u1",
            message_id: "m1",
            text: "hi"
          )

        # The greeting matcher answers without any LLM call — a crashing :llm
        # seam proves zero tokens were spent. (Variable-module call: the module
        # only exists at runtime, so a literal call would warn at compile time.)
        bot = Module.concat(["Demo", "Bot"])
        responder = bot.responder(llm: fn _req, _opts -> raise "no LLM expected" end)
        assert {:reply, reply} = responder.(imp, %{})
        assert reply =~ "Demo"
      end)
    end

    test "the generated system prompt is embedded from the prompt file", %{tmp: tmp} do
      in_tmp(tmp, fn ->
        Bot.run(["Demo"])
        compile!("lib/demo/fast/greeting.ex")
        compile!("lib/demo/routines/echo.ex")
        compile!("lib/demo/bot.ex")

        bot = Module.concat(["Demo", "Bot"])
        system = bot.system()
        assert system == File.read!("priv/prompts/demo/router.md")
        assert system =~ "router"
      end)
    end

    test "supports nested namespaces", %{tmp: tmp} do
      in_tmp(tmp, fn ->
        Bot.run(["MyApp.Support"])
        assert File.exists?("lib/my_app/support/bot.ex")
        assert File.exists?("priv/prompts/my_app/support/router.md")
      end)
    end

    test "rejects invalid module names" do
      assert_raise Mix.Error, ~r/valid module name/, fn ->
        Bot.run(["not_a_module"])
      end

      assert_raise Mix.Error, ~r/Expected a bot namespace/, fn ->
        Bot.run([])
      end
    end
  end

  describe "mix virtuoso.gen.routine" do
    test "generates a compiling routine and prints the registry entry", %{tmp: tmp} do
      in_tmp(tmp, fn ->
        Routine.run(["Demo", "Booking"])

        assert File.exists?("lib/demo/routines/booking.ex")
        [{mod, _} | _] = compile!("lib/demo/routines/booking.ex")
        assert mod == Demo.Routines.Booking

        imp =
          Impression.new(
            channel: :test,
            conversation_id: "c1",
            sender_id: "u1",
            message_id: "m1",
            text: "book it"
          )

        assert {:reply, reply} = mod.run(imp, %{})
        assert reply =~ "book it"

        assert Enum.any?(shell_infos(), &(&1 =~ ~s("booking" => Demo.Routines.Booking)))
      end)
    end
  end

  describe "mix virtuoso.gen.tool" do
    test "generates a compiling tool in the Tools namespace", %{tmp: tmp} do
      in_tmp(tmp, fn ->
        Tool.run(["Demo", "Weather"])

        assert File.exists?("lib/demo/tools/weather.ex")
        [{mod, _} | _] = compile!("lib/demo/tools/weather.ex")
        assert mod == Demo.Tools.Weather

        assert Enum.any?(shell_infos(), &(&1 =~ ~s("weather" => Demo.Tools.Weather)))
      end)
    end
  end
end
