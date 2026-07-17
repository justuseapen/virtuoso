defmodule Virtuoso.Routine do
  @moduledoc """
  Explicit routine registry — the replacement for the legacy `String.to_atom`
  dispatch.

  The 2018 code turned an intent *string* (from Wit/Watson, i.e. external input)
  into an atom with `String.to_atom` and dispatched on it. Atoms are never
  garbage-collected and the table is bounded, so untrusted strings could exhaust
  it — a denial-of-service. This registry looks routines up in an explicit
  **string-keyed map**, so an unknown or hostile name is a plain `:error`, and
  no atom is ever created from external input.

  A routine is a module implementing this behaviour. The registry is a
  `%{name => module}` map a bot assembles at compile time:

      @routines %{
        "greeting" => MyBot.Routines.Greeting,
        "time_left" => MyBot.Routines.TimeLeft
      }
  """

  alias Virtuoso.Impression

  @type registry :: %{optional(String.t()) => module()}
  @type context :: map()
  @type result :: {:reply, String.t()} | :noreply | {:error, term()}

  @doc "Run the routine against an impression and context."
  @callback run(Impression.t() | term(), context()) :: result()

  @doc """
  Resolve a routine name to its module.

  Returns `{:ok, module}` for a registered name and `:error` for anything else —
  a non-string, a name not in the registry, or a hostile string. Never creates
  an atom.
  """
  @spec fetch(registry(), term()) :: {:ok, module()} | :error
  def fetch(registry, name) when is_binary(name), do: Map.fetch(registry, name)
  def fetch(_registry, _name), do: :error

  @doc """
  Resolve and run a routine by name.

  Returns the routine's result, or `{:error, :unknown_routine}` if the name
  isn't registered.
  """
  @spec dispatch(registry(), term(), Impression.t() | term(), context()) ::
          result() | {:error, :unknown_routine}
  def dispatch(registry, name, impression, context) do
    case fetch(registry, name) do
      {:ok, module} -> module.run(impression, context)
      :error -> {:error, :unknown_routine}
    end
  end
end
