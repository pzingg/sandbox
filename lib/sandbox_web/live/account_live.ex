defmodule SandboxWeb.AccountLive do
  use SandboxWeb, :live_view

  require Logger

  alias OAuth2.Client
  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.{AuthUser, AuthRequestData}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Account")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Authenticated Account</h1>
    <div id="sandbox">
      <form>
        <dl>
          <dt>DID</dt>
          <dd>{@current_user.did}</dd>
          <dt>Handle</dt>
          <dd>{@current_user.handle}</dd>
          <dt>PDS</dt>
          <dd>{@current_user.pds_url}</dd>
          <dt>Scope</dt>
          <dd>{@current_user.scope}</dd>
          <dt>Access token</dt>
          <dd>{String.slice(@current_user.access_token, -8, 8)}</dd>
          <dt>Refresh token</dt>
          <dd>{String.slice(@current_user.refresh_token, -8, 8)}</dd>
          <dt>Access expires</dt>
          <dd>{expires(@current_user)}</dd>
        </dl>
        <p>
          You are now logged in!
        </p>
        <p>
          Click
          <a href={~p"/feed/following"}>
            <span class="px-2 py-1 rounded-lg bg-zinc-100 hover:bg-zinc-200/80">Following</span>
          </a>
          or one of the other feeds in the navigation bar to log see the most recent posts
        </p>
        <div class="flex">
          <div class="flex justify-center w-full gap-4">
            <button type="button" class="button" phx-click="refresh_token">
              Refresh token
            </button>
            <button type="button" class="button" phx-click="authorize">
              Sign in again
            </button>
          </div>
        </div>
      </form>
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

        _ = Bluesky.update_user(user)

        socket
        |> assign(:current_user, user)
        |> put_flash(:info, "Refreshed token!")
      else
        {:error, reason} ->
          put_flash(socket, :error, "Could not refresh token: #{reason}")
      end

    {:noreply, socket}
  end

  def handle_event("authorize", _params, socket) do
    %{current_user: current_user} = socket.assigns

    socket =
      with %{did: did, scope: scope} <- current_user,
           {:ok, %AuthRequestData{} = request_data} <-
             Bluesky.pushed_authorization_request(did, scope: scope) do
        authorize_url = Bluesky.authorize_url!(request_data)
        redirect(socket, external: authorize_url)
      else
        {:error, reason} ->
          put_flash(socket, :error, reason)
      end

    {:noreply, socket}
  end

  defp expires(user) do
    DateTime.from_unix!(user.expires_at) |> DateTime.to_iso8601(:extended)
  end
end
