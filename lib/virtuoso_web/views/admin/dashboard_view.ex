defmodule VirtuosoWeb.Admin.DashboardView do
  @moduledoc """
  View functions for the dashboard.
  """
  use VirtuosoWeb, :view

  def render("show.json", %{dashboard: dashboard}) do
    %{dashboard: dashboard}
  end
end
