defmodule VirtuosoWeb.PageController do
  use VirtuosoWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
