defmodule VirtuosoDashboardWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :virtuoso_dashboard

  @session_options [
    store: :cookie,
    key: "_virtuoso_dashboard",
    signing_salt: "vdash-session",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # No asset pipeline: Phoenix and LiveView ship prebuilt JS in their packages;
  # serve it straight from deps.
  plug Plug.Static, at: "/assets/phoenix", from: {:phoenix, "priv/static"}, gzip: false

  plug Plug.Static,
    at: "/assets/phoenix_live_view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false

  plug Plug.Session, @session_options
  plug VirtuosoDashboardWeb.Router
end
