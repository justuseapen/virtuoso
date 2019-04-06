use Mix.Config

config :fb_messenger, FbMessengerWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/brunch/bin/brunch",
      "watch",
      "--stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

config :fb_messenger, FbMessengerWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/fb_messenger_web/views/.*(ex)$},
      ~r{lib/fb_messenger_web/templates/.*(eex)$}
    ]
  ]

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :fb_messenger, :nlp, Wit.Client
config :fb_messenger, :fb_messenger_network, FbMessenger.FbMessenger.Network

# import_config "dev.secret.exs"
