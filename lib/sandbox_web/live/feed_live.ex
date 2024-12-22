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
    friends: "Popular With Friends",
    news: "News"
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> stream_configure(:posts, dom_id: &Feed.Post.stream_id/1)
      |> stream(:posts, [])
      |> assign(:feed_name, "")
      |> assign(:return_to, nil)
      |> assign(:feed, AsyncResult.loading())
      |> assign(:modal, AsyncResult.loading())
      |> assign(:show_modal, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = socket.assigns[:current_user]
    live_action = socket.assigns.live_action
    post_uri = Map.get(params, "post_uri")
    return_to = Map.get(params, "return_to")

    socket =
      cond do
        live_action in [:me, :following, :discover, :friends, :news] ->
          # :current_user assigned in MountHooks.on_mount(:user)

          socket
          |> stream(:posts, [], reset: true)
          |> assign(:feed_name, feed_display_name(live_action, user))
          |> assign(:return_to, nil)
          |> assign(:feed, AsyncResult.loading())
          |> start_async(:feed, fn ->
            case Bluesky.get_feed(user, live_action, limit: 50) do
              {:ok, feed} -> Feed.decode_feed(feed, user)
              error -> error
            end
          end)

        live_action == :thread && is_binary(post_uri) ->
          uri = SandboxWeb.decode_post_uri(post_uri)

          socket
          |> stream(:posts, [], reset: true)
          |> assign(:feed_name, "Thread")
          |> assign(:return_to, return_to)
          |> assign(:feed, AsyncResult.loading())
          |> start_async(:feed, fn ->
            case Bluesky.get_post_thread(uri, user) do
              {:ok, thread} -> Feed.decode_thread(thread, user)
              error -> error
            end
          end)

        true ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("modal-image", %{"src" => src, "alt" => alt}, socket) do
    socket =
      socket
      |> assign(:modal, AsyncResult.ok(%{type: :image, src: src, alt: alt}))
      |> assign(:show_modal, true)

    {:noreply, socket}
  end

  def handle_event("modal-thread", %{"post_uri" => post_uri, "reply" => _}, socket) do
    # We only display thread in modal if there is a reply to the post
    user = socket.assigns[:current_user]
    uri = SandboxWeb.decode_post_uri(post_uri)

    socket =
      socket
      |> start_async(:modal, fn ->
        case Bluesky.get_post_thread(uri, user) do
          {:ok, thread} -> Feed.decode_thread(thread, user)
          error -> error
        end
      end)
      |> assign(:show_modal, true)

    {:noreply, socket}
  end

  def handle_event("modal-thread", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("modal-cancel", _params, socket) do
    socket =
      socket
      |> assign(:modal, AsyncResult.loading())
      |> assign(:show_modal, false)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:feed, {:ok, {:ok, posts}}, socket) do
    %{feed: feed} = socket.assigns
    count = Enum.count(posts)

    socket =
      socket
      |> stream(:posts, posts)
      |> assign(:feed, AsyncResult.ok(feed, %{count: count}))

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

  def handle_async(:modal, {:ok, {:ok, posts}}, socket) do
    %{modal: modal} = socket.assigns

    posts = Enum.map(posts, fn post -> {Feed.Post.stream_id(post), post} end)

    socket =
      socket
      |> assign(:modal, AsyncResult.ok(modal, %{type: :thread, posts: posts}))

    {:noreply, socket}
  end

  def handle_async(:modal, {:ok, {:error, reason}}, socket) do
    %{modal: modal} = socket.assigns
    {:noreply, assign(socket, :modal, AsyncResult.failed(modal, reason))}
  end

  def handle_async(:modal, {:exit, reason}, socket) do
    %{modal: modal} = socket.assigns
    {:noreply, assign(socket, :modal, AsyncResult.failed(modal, reason))}
  end

  def feed_display_name(:me, user) do
    "@" <> user.handle
  end

  def feed_display_name(feed, _user) do
    Map.get(@feed_display_names, feed, "feed")
  end
end
