import Config

config :logger, level: :warning

# The whole suite runs offline: the LLM behaviour is served by an in-process
# mock that returns scripted responses instead of hitting the network.
config :virtuoso, :llm, Virtuoso.LLM.Mock

config :virtuoso, Virtuoso.Repo,
  username: System.get_env("PGUSER", System.get_env("USER", "postgres")),
  password: System.get_env("PGPASSWORD", ""),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "virtuoso_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
