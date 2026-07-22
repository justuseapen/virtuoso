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
    plug :put_conversation_id
  end

  # The ops dashboard is auth-gated (host-provided plug); chat is public.
  pipeline :admin do
    plug :dashboard_auth
  end

  scope "/", VirtuosoDashboardWeb do
    pipe_through :browser

    live "/", ChatLive
  end

  scope "/", VirtuosoDashboardWeb do
    pipe_through [:browser, :admin]

    live "/dashboard", DashboardLive
  end

  # Every visitor gets a stable per-browser conversation id — the identity the
  # event log, budget caps, and engine panel all key on.
  defp put_conversation_id(conn, _opts) do
    case get_session(conn, "conversation_id") do
      nil ->
        id = "web-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
        put_session(conn, "conversation_id", id)

      _id ->
        conn
    end
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
