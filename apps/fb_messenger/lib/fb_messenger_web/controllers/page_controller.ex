defmodule FbMessengerWeb.PageController do
  use FbMessengerWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
