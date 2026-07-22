import Config

# Dev-only demo app — these secrets are deliberately static and NOT for
# production deployment. Dashboard auth (a host-provided plug) is Phase 4.
config :virtuoso_dashboard, VirtuosoDashboardWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4040],
  adapter: Bandit.PhoenixAdapter,
  server: true,
  # Dev demo binds 127.0.0.1 but url host is "localhost" — skip the websocket
  # origin check so either hostname works. Never do this in production.
  check_origin: false,
  secret_key_base: "virtuoso-dashboard-dev-only-secret-key-base-0123456789abcdefghijklmn",
  live_view: [signing_salt: "virtuoso-dash-lv"],
  pubsub_server: VirtuosoDashboard.PubSub,
  render_errors: [formats: [html: VirtuosoDashboardWeb.ErrorHTML], layout: false]

# The observed framework's repo (the dashboard boots :virtuoso as a dependency).
config :virtuoso, ecto_repos: [Virtuoso.Repo]

config :virtuoso, Virtuoso.Repo,
  username: System.get_env("PGUSER", System.get_env("USER", "postgres")),
  password: System.get_env("PGPASSWORD", ""),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "virtuoso_dev",
  pool_size: 5

config :virtuoso, :llm, Virtuoso.LLM.Anthropic
config :virtuoso, Virtuoso.LLM.Anthropic, api_key: {:system, "ANTHROPIC_API_KEY"}

config :logger, level: :info
config :phoenix, :json_library, Jason

if config_env() == :test do
  # Offline + isolated: stub adapter, sandboxed dedicated database, no server.
  config :virtuoso_dashboard, VirtuosoDashboardWeb.Endpoint, server: false

  config :virtuoso, :llm, VirtuosoDashboard.LLMStub

  config :virtuoso, Virtuoso.Repo,
    database: "virtuoso_dashboard_test",
    pool: Ecto.Adapters.SQL.Sandbox
end
