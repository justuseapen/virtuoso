defmodule Virtuoso.Ensemble.Config do
  @moduledoc """
  Ensemble configuration — per-bot defaults with per-routine overrides.

  A bot declares default ensemble settings (`ensemble: [n: 3, strategy: :majority,
  models: [...]]`); an individual routine can override any field for its own
  consensus (`ensemble: [n: 5, strategy: :judge]`). `merge/2` layers the routine
  override onto the bot defaults field-by-field, and `resolve/1` normalizes the
  result — mapping strategy names (`:majority`/`:quorum`/`:judge`) to strategy
  modules and applying defaults.

  `to_ensemble_opts/1` renders the resolved config into the keyword shape
  `Virtuoso.Thinking.Slow` / `Virtuoso.Ensemble.run/2` expect.
  """

  alias Virtuoso.Ensemble.Strategy.{Judge, Majority, Quorum}

  @default_n 3
  @default_strategy Majority

  @type t :: %__MODULE__{
          n: pos_integer(),
          strategy: module(),
          models: [String.t()],
          strategy_opts: keyword()
        }

  defstruct n: @default_n, strategy: @default_strategy, models: [], strategy_opts: []

  @strategies %{majority: Majority, quorum: Quorum, judge: Judge}

  @doc "Normalize an ensemble keyword list into a `%Config{}`."
  @spec resolve(keyword()) :: t()
  def resolve(opts) do
    %__MODULE__{
      n: Keyword.get(opts, :n, @default_n),
      strategy: resolve_strategy(Keyword.get(opts, :strategy, @default_strategy)),
      models: Keyword.get(opts, :models, []),
      strategy_opts: Keyword.get(opts, :strategy_opts, [])
    }
  end

  @doc """
  Merge a per-routine override (keyword list or nil) onto per-bot defaults,
  then resolve. The override wins field-by-field; omitted fields inherit.
  """
  @spec merge(keyword(), keyword() | nil) :: t()
  def merge(defaults, nil), do: resolve(defaults)

  def merge(defaults, override) do
    defaults |> Keyword.merge(override) |> resolve()
  end

  @doc "Render a resolved config as the keyword opts `Slow`/`Ensemble` consume."
  @spec to_ensemble_opts(t()) :: keyword()
  def to_ensemble_opts(%__MODULE__{} = c) do
    [n: c.n, strategy: c.strategy, models: c.models, strategy_opts: c.strategy_opts]
  end

  # Accept a strategy module directly, or map a known name to its module.
  defp resolve_strategy(strategy) when is_atom(strategy) do
    cond do
      Map.has_key?(@strategies, strategy) -> Map.fetch!(@strategies, strategy)
      strategy_module?(strategy) -> strategy
      true -> raise ArgumentError, "unknown strategy: #{inspect(strategy)}"
    end
  end

  # A module (not one of the short names) is assumed to be a Strategy impl.
  defp strategy_module?(strategy) do
    Code.ensure_loaded?(strategy) and function_exported?(strategy, :aggregate, 2)
  end
end
