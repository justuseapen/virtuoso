defmodule VirtuosoWeb.Router do
  use VirtuosoWeb, :router

  defmacro __using__(_opts \\ []) do
    quote do
      import unquote(__MODULE__)
    end
  end

  defmacro admin_routes_and_pipelines(_opts \\ []) do
    quote do
      pipeline :unprotected_browser do
        plug(:accepts, ["html"])
        plug(:fetch_session)
        plug(:fetch_flash)
        plug(:put_secure_browser_headers)
      end

      pipeline :api do
        plug(:accepts, ["json"])
      end

      scope "/" do
        pipe_through :unprotected_browser
        get "/admin/dashboard", VirtuosoWeb.Admin.DashboardController, :dashboard
      end
    end
  end
end
