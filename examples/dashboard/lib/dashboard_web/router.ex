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
  end

  scope "/", VirtuosoDashboardWeb do
    pipe_through :browser

    live "/", DashboardLive
  end
end
