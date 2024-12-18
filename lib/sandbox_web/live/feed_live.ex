defmodule SandboxWeb.FeedLive do
  use SandboxWeb, :live_view

  require Logger

  import SandboxWeb.Bluesky.FeedComponents

  alias Phoenix.LiveView.AsyncResult
  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.Feed

  @feed_display_names %{
    following: "Following",
    discover: "Discover",
    friends: "Popular with Friends",
    news: "News"
  }

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

  @impl true
  def handle_params(_params, _uri, socket) do
    live_action = socket.assigns.live_action

    socket =
      if live_action in [:me, :following, :discover, :friends, :news] do
        # :current_user assigned in MountHooks.on_mount(:user)
        user = socket.assigns[:current_user]

        socket
        |> stream(:posts, [], reset: true)
        |> assign(:feed_name, feed_display_name(live_action, user))
        |> assign(:feed, AsyncResult.loading())
        |> start_async(:feed, fn ->
          case Bluesky.get_feed(user, live_action, limit: 50) do
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
    <div id="feed-container">
      <.async_result :let={feed} :if={@live_action != :index} assign={@feed}>
        <:loading>
          <div class="my-4 text-lg">Loading <span class="font-bold">{@feed_name}</span>...</div>
        </:loading>
        <:failed :let={reason}>There was an error loading the feed {reason}</:failed>
        <h2 class="my-4 text-2xl">
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

  def feed_display_name(:me, user) do
    "@" <> user.handle
  end

  def feed_display_name(feed, _user) do
    Map.get(@feed_display_names, feed, "feed")
  end
end
