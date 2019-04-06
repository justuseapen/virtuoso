defmodule FbMessengerWeb.PageControllerTest do
  use FbMessengerWeb.ConnCase

  test "GET /", %{conn: conn} do
    response =
      conn
      |> get(page_path(conn, :index))
      |> response(200)

    assert response =~ "Welcome to Phoenix!"
  end
end
