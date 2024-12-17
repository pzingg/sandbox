defmodule SandboxWeb.AccountLive do
  use SandboxWeb, :live_view

  require Logger

  import SandboxWeb.Bluesky.FeedComponents

  alias Phoenix.LiveView.AsyncResult
  alias OAuth2.Client
  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.{AuthUser, AuthRequestData, Feed}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> stream_configure(:posts, dom_id: &Feed.posts_stream_id/1)
      |> stream(:posts, [])
      |> assign(:feed_name, "")
      |> assign(:feed, AsyncResult.loading(%{}))

    {:ok, socket}
  end

  @feed_display_names %{
    following: "Following",
    discover: "Discover",
    friends: "Popular with Friends",
    news: "News"
  }

  @impl true
  def handle_params(_params, _uri, socket) do
    live_action = socket.assigns.live_action

    socket =
      if live_action in [:following, :discover, :friends, :news] do
        # :current_user assigned in MountHooks.on_mount(:user)
        user = socket.assigns[:current_user]

        socket
        |> stream(:posts, [], reset: true)
        |> assign(:feed_name, Map.get(@feed_display_names, live_action))
        |> assign(:feed, AsyncResult.loading())
        |> start_async(:feed, fn ->
          case Bluesky.get_feed(user, live_action, limit: 10) do
            {:ok, feed} -> Feed.decode_feed(feed, user)
            error -> error
          end
        end)
      else
        socket
      end

    {:noreply, socket}
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
        <button type="button" class="button" phx-click="refresh_token">
          Refresh token
        </button>
        <button type="button" class="button" phx-click="authorize">
          Log in again
        </button>
      </form>
      <div class="grid grid-cols-2 gap-x-4">
        <button type="button" class="mx-auto button">
          <.link patch={~p"/account/feed/following"}>Following</.link>
        </button>
        <button type="button" class="mx-auto button">
          <.link patch={~p"/account/feed/discover"}>Discover</.link>
        </button>
        <button type="button" class="mx-auto button">
          <.link patch={~p"/account/feed/friends"}>
            Popular With Friends
          </.link>
        </button>
        <button type="button" class="mx-auto button">
          <.link patch={~p"/account/feed/news"}>News</.link>
        </button>
      </div>

      <.async_result :let={feed} :if={@live_action != :index} assign={@feed}>
        <:loading>
          <div class="my-4 text-lg">Loading <span class="font-bold">{@feed_name}</span>...</div>
        </:loading>
        <:failed :let={reason}>There was an error loading the feed {reason}</:failed>
        <h2 class="my-4 text-lg">
          {feed} recent posts from <span class="font-bold">{@feed_name}</span>
        </h2>
        <ul id="feed" class="feed" phx-update="stream">
          <li :for={{dom_id, post} <- @streams.posts} id={dom_id}>
            <.skeet post={post} />
          </li>
        </ul>
      </.async_result>
    </div>
    """
  end

  @impl true
  def handle_async(:feed, {:ok, {:ok, posts}}, socket) do
    %{feed: feed} = socket.assigns
    count = Enum.count(posts)

    if count > 0 do
      post = hd(posts)
      _ = Feed.decode_post_thread(post.uri, socket.assigns.current_user)
    end

    socket =
      socket
      |> stream(:posts, posts)
      |> assign(:feed, AsyncResult.ok(feed, count))

    {:noreply, socket}
  end

  def handle_async(:feed, {:ok, {:error, reason}}, socket) do
    %{feed: feed} = socket.assigns
    {:noreply, assign(socket, :feed, AsyncResult.failed(feed, reason))}
  end

  def handle_async(:feed, {:exit, reason}, socket) do
    %{feed: feed} = socket.assigns
    {:noreply, assign(socket, :feed, AsyncResult.failed(feed, reason))}
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
