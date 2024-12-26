defmodule SandboxWeb.Authentication do
  @moduledoc """
  Minimal Phoenix authentication.
  """

  use SandboxWeb, :controller

  require Logger

  @doc """
  Function plug used for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    cond do
      logged_in?(conn) ->
        conn

      true ->
        conn
        |> put_flash(:error, "You must sign in to access this page.")
        |> redirect(to: ~p"/")
        |> halt()
    end
  end

  def log_in_user(conn, user) do
    conn
    |> assign(:current_user, user)
    |> put_session("did", user.did)
    |> put_session("access_token", user.access_token)
    |> put_flash(:info, "Access granted to #{user.handle}")
  end

  @doc """
  See if there is a user in the connection.
  """
  def logged_in?(conn) do
    case current_user(conn) do
      %{did: _did} ->
        true

      _ ->
        false
    end
  end

  def current_user(conn) do
    conn.assigns[:current_user]
  end
end
