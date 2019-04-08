# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :slack_messaging,
  namespace: SlackMessaging

# Configures the endpoint
config :slack_messaging, SlackMessagingWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "dlGETHXUlMWnRvtpdJwedtY7pZGItl0hD3E5Mxjf9AFydd+ySOHaTx7M8IihWxUE",
  render_errors: [view: SlackMessagingWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: SlackMessaging.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:user_id]

config :slack_messaging,
  client_id: System.get_env("SLACK_CLIENT_ID"),
  client_secret: System.get_env("SLACK_CLIENT_SECRET"),
  root_url: System.get_env("SLACK_ROOT_URL")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
