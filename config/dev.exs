import Config

config :logger, :console, format: "[$level] $message\n"

config :virtuoso, Virtuoso.Repo,
  username: System.get_env("PGUSER", System.get_env("USER", "postgres")),
  password: System.get_env("PGPASSWORD", ""),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "virtuoso_dev",
  pool_size: 10
