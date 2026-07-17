import Config

config :virtuoso, ecto_repos: [Virtuoso.Repo]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:conversation_id, :model]

# The LLM adapter the framework uses by default. Overridden in test to keep
# the suite fully offline.
config :virtuoso, :llm, Virtuoso.LLM.Anthropic

# Anthropic adapter: API key from the environment (never committed).
config :virtuoso, Virtuoso.LLM.Anthropic, api_key: {:system, "ANTHROPIC_API_KEY"}

import_config "#{config_env()}.exs"
