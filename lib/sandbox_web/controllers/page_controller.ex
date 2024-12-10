defmodule SandboxWeb.PageController do
  use SandboxWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def tos(conn, _params) do
    render(conn, :tos)
  end

  def policy(conn, _params) do
    render(conn, :policy)
  end
end
