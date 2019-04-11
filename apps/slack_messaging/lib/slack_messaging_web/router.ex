defmodule SlackMessagingWeb.Router do
  use SlackMessagingWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SlackMessagingWeb, as: :api do
    pipe_through :api

    scope "/v1", V1, as: :v1 do
      get("/auth/:provider", SlackAuthController, :request)
    end

  end

end
