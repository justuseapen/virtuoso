defmodule VirtuosoDashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :virtuoso_dashboard,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
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
      {:jason, "~> 1.4"}
    ]
  end
end
