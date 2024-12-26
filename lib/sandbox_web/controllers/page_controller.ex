defmodule SandboxWeb.PageController do
  use SandboxWeb, :controller

  def tos(conn, _params) do
    render(conn, :tos, page_title: "Terms of Service")
  end

  def policy(conn, _params) do
    render(conn, :policy, page_title: "Privacy Policy")
  end
end
