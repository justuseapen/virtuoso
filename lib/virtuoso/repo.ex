defmodule Virtuoso.Repo do
  @moduledoc """
  The framework's Ecto repo, backing the conversation event log.

  The event log is the source of truth for conversation state: recovery is a
  replay from this log, and exactly-once processing is enforced by a unique
  index on each event's dedup key. Postgres is chosen over ETS/Mnesia because
  the log must survive the process (and the node) that produced it — see the
  plan's "persistence precedes fabric" decision.
  """
  use Ecto.Repo,
    otp_app: :virtuoso,
    adapter: Ecto.Adapters.Postgres
end
