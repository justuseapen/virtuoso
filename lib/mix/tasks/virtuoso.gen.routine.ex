defmodule Mix.Tasks.Virtuoso.Gen.Routine do
  @shortdoc "Generates a Virtuoso routine module"

  @moduledoc """
  Generates a routine under an existing bot namespace:

      mix virtuoso.gen.routine Demo Booking

  creates `lib/demo/routines/booking.ex` defining `Demo.Routines.Booking`, and
  prints the registry entry to add to `Demo.Bot.routines/0`. The registry is
  string-keyed on purpose — routes resolve by map lookup, never `String.to_atom`.
  """

  use Mix.Task

  import Mix.Generator

  alias Mix.Virtuoso, as: Gen

  @impl true
  def run(argv) do
    case argv do
      [namespace, name | _] ->
        {module, path} = Gen.module_arg!(namespace, "bot namespace")
        {routine, routine_path} = Gen.module_arg!(name, "routine name")
        generate(module, path, routine, routine_path)

      _ ->
        Mix.raise("Expected a namespace and a name, e.g.: mix virtuoso.gen.routine Demo Booking")
    end
  end

  defp generate(module, path, routine, routine_path) do
    key = String.replace(routine_path, "/", "_")
    assigns = [module: module, routine: routine, key: key]

    create_file(
      Path.join(["lib", path, "routines", "#{routine_path}.ex"]),
      routine_template(assigns)
    )

    Mix.shell().info("""

    Add it to #{module}.Bot.routines/0:

        "#{key}" => #{module}.Routines.#{routine}

    or with a per-routine ensemble override:

        "#{key}" => {#{module}.Routines.#{routine}, ensemble: [n: 5, strategy: :judge]}
    """)
  end

  embed_template(:routine, """
  defmodule <%= @module %>.Routines.<%= @routine %> do
    @moduledoc \"\"\"
    Handles the "<%= @key %>" intent. Runs exactly once, after the ensemble has
    committed to this route — put side effects here, never in members.
    \"\"\"

    @behaviour Virtuoso.Routine

    alias Virtuoso.Impression

    @impl true
    def run(%Impression{} = impression, _context) do
      {:reply, "<%= @routine %> is not implemented yet (you said: \#{impression.text})"}
    end
  end
  """)
end
