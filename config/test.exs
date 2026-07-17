import Config

config :logger, level: :warning

# The whole suite runs offline: the LLM behaviour is served by an in-process
# mock that returns scripted responses instead of hitting the network.
config :virtuoso, :llm, Virtuoso.LLM.Mock
