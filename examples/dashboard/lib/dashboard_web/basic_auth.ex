defmodule VirtuosoDashboardWeb.BasicAuth do
  @moduledoc "HTTP basic auth for the ops dashboard (plugged via the :auth hook)."

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts), do: Plug.BasicAuth.basic_auth(conn, opts)
end
