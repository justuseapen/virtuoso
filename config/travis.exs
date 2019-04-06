use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :virtuoso, VirtuosoWeb.Endpoint,
  http: [port: 4001],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn
config :virtuoso, :nlp, Virtuoso.NLPMock
config :virtuoso, :fb_messenger_network, Virtuoso.FbMessenger.Network.Mock
config :virtuoso, :facebook_graph_api, Virtuoso.FacebookGraphApi.HttpMock

config :virtuoso, :bots, [
  BotMock
]
