defmodule SlackMessagingWeb.Router do
  use SlackMessagingWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SlackMessagingWeb do
    pipe_through :api

    get("/auth", SlackAuthController, :request)
  end

end
