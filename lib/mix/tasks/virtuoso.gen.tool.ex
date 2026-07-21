defmodule Mix.Tasks.Virtuoso.Gen.Tool do
  @shortdoc "Generates a Virtuoso tool module (a post-consensus side-effect routine)"

  @moduledoc """
  Generates a tool under an existing bot namespace:

      mix virtuoso.gen.tool Demo Weather

  creates `lib/demo/tools/weather.ex` defining `Demo.Tools.Weather`.

  In Virtuoso 0.1.0 a *tool* is a `Virtuoso.Routine` in the `Tools` namespace:
  the ensemble votes on the route, and the winning tool performs its side effect
  (API call, DB write, message send) **exactly once, post-consensus** — N members
  never mean N side effects. Register it in the bot's routine registry like any
  routine.
  """

  use Mix.Task

  import Mix.Generator

  alias Mix.Virtuoso, as: Gen

  @impl true
  def run(argv) do
    case argv do
      [namespace, name | _] ->
        {module, path} = Gen.module_arg!(namespace, "bot namespace")
        {tool, tool_path} = Gen.module_arg!(name, "tool name")
        generate(module, path, tool, tool_path)

      _ ->
        Mix.raise("Expected a namespace and a name, e.g.: mix virtuoso.gen.tool Demo Weather")
    end
  end

  defp generate(module, path, tool, tool_path) do
    key = String.replace(tool_path, "/", "_")
    assigns = [module: module, tool: tool, key: key]

    create_file(Path.join(["lib", path, "tools", "#{tool_path}.ex"]), tool_template(assigns))

    Mix.shell().info("""

    Add it to #{module}.Bot.routines/0:

        "#{key}" => #{module}.Tools.#{tool}
    """)
  end

  embed_template(:tool, """
  defmodule <%= @module %>.Tools.<%= @tool %> do
    @moduledoc \"\"\"
    A tool: a routine whose job is a side effect. It runs exactly once, after
    the ensemble has committed to the "<%= @key %>" route — the consensus layer
    guarantees N members never trigger N side effects.
    \"\"\"

    @behaviour Virtuoso.Routine

    alias Virtuoso.Impression

    @impl true
    def run(%Impression{} = impression, _context) do
      # Perform the side effect here (HTTP call, DB write, ...), then reply.
      {:reply, "<%= @tool %> is not implemented yet (you said: \#{impression.text})"}
    end
  end
  """)
end
