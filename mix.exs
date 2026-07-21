defmodule Virtuoso.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/justuseapen/virtuoso"

  def project do
    [
      app: :virtuoso,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      description: description(),
      package: package(),
      name: "Virtuoso",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Virtuoso.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # HTTP client for LLM adapters.
      {:req, "~> 0.6"},
      {:jason, "~> 1.4"},
      # Persistence for the conversation event log (Phase 1).
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      # Observability: every LLM call emits telemetry.
      {:telemetry, "~> 1.2"},
      # Distributed fabric (Phase 3): cluster-wide registry/supervision.
      {:horde, "~> 0.10"},
      # Cluster formation (gossip for dev, DNS for Fly.io); no-op unless configured.
      {:libcluster, "~> 3.3"},
      # Multi-node spike/chaos drills (test-only; @tag :distributed).
      {:local_cluster, "~> 2.1", only: [:test]},
      # Dev/test tooling.
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit, :mix],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  defp description do
    """
    A BEAM-native AI-agent orchestration framework: actor-based parallel
    consensus (ensembles) and a distributed compute fabric, built on OTP.
    """
  end

  defp package do
    [
      files: ~w(lib mix.exs README* LICENSE*),
      maintainers: ["Justus Eapen"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
