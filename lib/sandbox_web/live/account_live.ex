defmodule SandboxWeb.AccountLive do
  use SandboxWeb, :live_view

  require Logger

  alias OAuth2.Client
  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.{AuthUser, PushedAuthRequest}

  @impl true
  def mount(_params, _session, socket) do
    # :current_user assigned in MountHooks.on_mount(:user)
    Logger.debug("AccountLive mount #{inspect(socket.assigns)}")

    {:ok, assign(socket, :scope, Sandbox.Application.bluesky_client_scope())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Authenticated Account</h1>
    <div id="sandbox">
      <p>DID: {@current_user.did}</p>
      <p>Handle: {@current_user.handle}</p>
      <p>PDS: {@current_user.pds_url}</p>
      <p>Access Token: {String.slice(@current_user.access_token, -8, 8)}</p>
      <p>Refresh Token: {String.slice(@current_user.refresh_token, -8, 8)}</p>
      <button type="button" class="button" phx-click="refresh_token">
        Refresh Token
      </button>
      <button type="button" class="button" phx-click="authorize">
        Re-Authorize
      </button>
    </div>
    """
  end

  @impl true
  def handle_event("refresh_token", _params, socket) do
    socket =
      with user when is_map(user) <- socket.assigns[:current_user],
           {:ok, %Client{token: token}} <- Bluesky.refresh_token(user.did) do
        user = %AuthUser{
          user
          | access_token: token.access_token,
            expires_at: token.expires_at,
            scope: token.scope,
            refresh_token: token.refresh_token
        }

        Bluesky.update_user(user)
        put_flash(socket, :info, "Refreshed token!")
      else
        {:error, reason} ->
          put_flash(socket, :error, "Could not refresh token: #{reason}")
      end

    {:noreply, socket}
  end

  def handle_event("authorize", _params, socket) do
    socket =
      with user when is_map(user) <- socket.assigns[:current_user],
           {:ok, %PushedAuthRequest{client: client, authorize_params: params}} <-
             Bluesky.authorization_flow(user.did, socket.assigns[:scope]) do
        authorize_url = Bluesky.authorize_url!(client, params)
        Logger.info("redirecting to #{inspect(authorize_url)}")
        redirect(socket, external: authorize_url)
      else
        {:error, reason} ->
          put_flash(socket, :error, reason)
      end

    {:noreply, socket}
  end
end
