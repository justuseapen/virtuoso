defmodule Virtuoso.Bot do
  @moduledoc """
  The bot-definition API — the ensemble config surface.

  A bot declares its fast-thinkers, its routines, and its default ensemble
  settings; `use Virtuoso.Bot` gives it a ready-to-plug `responder/1` and the
  helpers that wire the thinking pipeline with the bot's config.

      defmodule MyBot do
        use Virtuoso.Bot

        @impl true
        def fast, do: [MyBot.Fast.Greeting]

        @impl true
        def ensemble, do: [n: 3, strategy: :majority]   # bot defaults

        @impl true
        def routines do
          %{
            "book"    => MyBot.Routines.Book,
            # a routine can override the bot's ensemble config for its own consensus
            "extract" => {MyBot.Routines.Extract, ensemble: [n: 5, strategy: :judge]}
          }
        end
      end

  A routine value is either a bare module or `{module, ensemble: [...]}`. The
  override is merged onto the bot defaults per field (`Virtuoso.Ensemble.Config`),
  so `ensemble_for/1` gives the resolved config for any routine.

  `Virtuoso.Conversation.deliver(imp, responder: MyBot.responder())` runs a
  message through the bot.
  """

  alias Virtuoso.Ensemble.Config
  alias Virtuoso.Thinking

  @doc "Fast-thinker modules (default `[]`)."
  @callback fast() :: [module()]

  @doc """
  The routine registry: `%{name => module | {module, ensemble: keyword()}}`.
  """
  @callback routines() :: %{optional(String.t()) => module() | {module(), keyword()}}

  @doc "Default ensemble config for routing (default `[]` → framework defaults)."
  @callback ensemble() :: keyword()

  # The generated functions fully-qualify Virtuoso.Bot.* on purpose — aliases
  # don't cross the quote boundary into the using module — so AliasUsage's
  # suggestion doesn't apply to this macro.
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage
  defmacro __using__(_opts) do
    quote do
      @behaviour Virtuoso.Bot

      @impl true
      def fast, do: []

      @impl true
      def routines, do: %{}

      @impl true
      def ensemble, do: []

      defoverridable fast: 0, routines: 0, ensemble: 0

      @doc "The routine registry with per-routine overrides stripped to modules."
      def routine_registry, do: Virtuoso.Bot.routine_registry(routines())

      @doc "The resolved ensemble config for a routine (bot defaults ⊕ override)."
      def ensemble_for(name), do: Virtuoso.Bot.ensemble_for(ensemble(), routines(), name)

      @doc """
      The `Virtuoso.Conversation` responder for this bot. `opts` are forwarded to
      the thinking pipeline (e.g. `:llm` to inject an adapter in tests).
      """
      def responder(opts \\ []), do: Virtuoso.Bot.responder(__MODULE__, opts)
    end
  end

  # --- helpers (used by the generated functions) ----------------------------

  @doc false
  def routine_registry(routines) do
    Map.new(routines, fn
      {name, {module, _override}} -> {name, module}
      {name, module} -> {name, module}
    end)
  end

  @doc false
  def ensemble_for(bot_defaults, routines, name) do
    override =
      case Map.get(routines, name) do
        {_module, opts} -> Keyword.get(opts, :ensemble)
        _ -> nil
      end

    Config.merge(bot_defaults, override)
  end

  @doc false
  def responder(bot, opts) do
    ensemble_opts = bot.ensemble() |> Config.resolve() |> Config.to_ensemble_opts()

    pipeline_opts =
      [
        fast: bot.fast(),
        routines: bot.routine_registry(),
        ensemble: ensemble_opts
      ]
      |> Keyword.merge(opts)

    Thinking.responder(pipeline_opts)
  end
end
