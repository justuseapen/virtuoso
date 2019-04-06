use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fb_messenger, FbMessengerWeb.Endpoint,
  http: [port: 4001],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

config :fb_messenger, :fb_messenger_network, FbMessenger.FbMessenger.Network.Mock
config :fb_messenger, :nlp, FbMessenger.NLPMock
config :fb_messenger, :facebook_graph_api, FbMessenger.FacebookGraphApi.HttpMock

config :fb_messenger, :bots, [
  BotMock
]
