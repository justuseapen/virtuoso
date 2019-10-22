defmodule VirtuosoWeb.Admin.DashboardController do
  @moduledoc """

  """
  use VirtuosoWeb, :controller
  alias Virtuoso.Admin.Dashboard

  @doc """
      List out all default and user generated bots       
  """
  def index(conn, _params) do
    with bots <- Dashboard.list_bots() do
      render(conn, "show.json", dashboard: bots)
    end
  end

  def create(conn, params) do
    response = Dashboard.send_message(params)

    render(conn, "show.json", dashboard: response)
  end
end
