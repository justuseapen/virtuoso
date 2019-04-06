defmodule FbMessengerWeb.Router do
  use FbMessengerWeb, :router

  pipeline :unprotected_browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:put_secure_browser_headers)
  end

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", FbMessengerWeb do
    pipe_through(:unprotected_browser)

    get("/", PageController, :index)
    get("/webhook", WebhookController, :verify)
    post("/webhook", WebhookController, :create)
  end

  scope "/admin", FbMessengerWeb.Admin do
    pipe_through(:browser)

    get("/", DashboardController, :index)
  end

  # Other scopes may use custom stacks.
  # scope "/api", FbMessengerWeb do
  #   pipe_through :api
  # end
end
