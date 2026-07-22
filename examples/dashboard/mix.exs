defmodule VirtuosoDashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :virtuoso_dashboard,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {VirtuosoDashboard.Application, []}
    ]
  end

  defp deps do
    [
      # The framework under observation (starts its own supervision tree).
      {:virtuoso, path: "../.."},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:floki, ">= 0.34.0", only: :test}
    ]
  end
end
