defmodule VirtuosoWeb.Router do
  use VirtuosoWeb, :router

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

  scope "/", VirtuosoWeb do
    pipe_through(:unprotected_browser)

    get("/", PageController, :index)
    get("/webhook", WebhookController, :verify)
    post("/webhook", WebhookController, :create)
  end

  scope "/api", VirtuosoWeb do
    pipe_through(:api)

    scope "/admin", Admin do
      pipe_through(:browser)
      resources("/bots", DashboardController, only: [:create, :index])
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", VirtuosoWeb do
  #   pipe_through :api
  # end
end
