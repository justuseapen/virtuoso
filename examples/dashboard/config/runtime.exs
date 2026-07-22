import Config

if config_env() == :prod do
  host = System.get_env("PHX_HOST", "virtuoso-showcase.fly.dev")
  port = String.to_integer(System.get_env("PORT", "8080"))

  config :virtuoso_dashboard, VirtuosoDashboardWeb.Endpoint,
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    check_origin: ["https://#{host}"],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    server: true

  config :virtuoso, Virtuoso.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :virtuoso, Virtuoso.LLM.Anthropic, api_key: {:system, "ANTHROPIC_API_KEY"}

  # The public demo's spend ceiling. Tune without redeploying.
  config :virtuoso, Virtuoso.Budget,
    per_conversation_daily:
      String.to_integer(System.get_env("BUDGET_PER_CONVERSATION_DAILY", "10000")),
    global_daily: String.to_integer(System.get_env("BUDGET_GLOBAL_DAILY", "500000"))

  # Ops dashboard behind basic auth; chat stays public.
  config :virtuoso_dashboard,
         :auth,
         {VirtuosoDashboardWeb.BasicAuth,
          username: System.get_env("DASHBOARD_USER", "admin"),
          password: System.fetch_env!("DASHBOARD_PASSWORD")}

  # Model overrides only — max_tokens keeps its config.exs value (Config
  # deep-merges keyword lists).
  config :virtuoso_dashboard, :chat,
    routing_model: System.get_env("ROUTING_MODEL", "claude-haiku-4-5"),
    generation_model: System.get_env("GENERATION_MODEL", "claude-opus-4-8")
end
