import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:conversation_id, :model]

# The LLM adapter the framework uses by default. Overridden in test to keep
# the suite fully offline.
config :virtuoso, :llm, Virtuoso.LLM.Anthropic

import_config "#{config_env()}.exs"
