# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Configures the endpoint
config :virtuoso, VirtuosoWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "po4C5BMidMUgoCWobtDqWrNNklWGB8Y3BqCZDraQBDB9KI3U6efR2HUMDkGx5gQ8",
  render_errors: [view: VirtuosoWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Virtuoso.PubSub, adapter: Phoenix.PubSub.PG2],
  http: [port: {:system, "PORT"}]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :virtuoso,
  facebook_graph_api: Virtuoso.FacebookGraphApi.Http

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
