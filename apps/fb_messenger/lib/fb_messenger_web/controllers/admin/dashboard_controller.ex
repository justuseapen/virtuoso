defmodule FbMessengerWeb.Admin.DashboardController do
  @moduledoc """

  """
  use FbMessengerWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
  
end
