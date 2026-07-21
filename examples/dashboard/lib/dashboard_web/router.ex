defmodule VirtuosoDashboardWeb.Router do
  use Phoenix.Router, helpers: false

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_root_layout, html: {VirtuosoDashboardWeb.Layouts, :root}
    plug :dashboard_auth
  end

  scope "/", VirtuosoDashboardWeb do
    pipe_through :browser

    live "/", DashboardLive
  end

  # Host-provided auth hook: point the config at any plug and every dashboard
  # request goes through it before rendering.
  #
  #     config :virtuoso_dashboard, :auth, MyApp.AdminAuth
  #     config :virtuoso_dashboard, :auth, {MyApp.BasicAuth, realm: "dashboard"}
  #
  # Unset → open access (dev only; the README says so out loud).
  defp dashboard_auth(conn, _opts) do
    case Application.get_env(:virtuoso_dashboard, :auth) do
      nil -> conn
      {plug, opts} -> plug.call(conn, plug.init(opts))
      plug when is_atom(plug) -> plug.call(conn, plug.init([]))
    end
  end
end
