# :distributed drills (multi-node Horde spike/chaos tests) are excluded by
# default — run them with: mix test --include distributed
ExUnit.start(exclude: [:distributed])

Ecto.Adapters.SQL.Sandbox.mode(Virtuoso.Repo, :manual)
