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
      |> assign(
        return_to: nil,
        post_thread: nil,
        page_title: "Feeds",
        feed_name: "",
        feed: AsyncResult.loading(),
        modal: AsyncResult.loading(),
        show_modal: false
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = socket.assigns[:current_user]
    live_action = socket.assigns.live_action

    socket =
      cond do
        live_action in [:me, :following, :discover, :friends, :news] ->
          title = feed_display_name(live_action, user)

          socket
          |> stream(:posts, [], reset: true)
          |> assign(
            return_to: "/feed/#{live_action}",
            post_thread: nil,
            page_title: title,
            feed_name: title,
            feed: AsyncResult.loading()
          )
          |> start_async(:feed, fn ->
            case Bluesky.get_feed(user, live_action, limit: 50) do
              {:ok, feed} -> Feed.decode_feed(feed, user)
              error -> error
            end
          end)

        live_action == :thread ->
          title = "Thread"
          post_uri = params["post_uri"]

          if post_uri do
            post_uri = Feed.decode_post_uri(post_uri)

            root_uri =
              case params["root_uri"] do
                root_uri when is_binary(root_uri) ->
                  Feed.decode_post_uri(root_uri)

                _ ->
                  Bluesky.resolve_root_uri(post_uri, user)
              end

            socket
            |> stream(:posts, [], reset: true)
            |> assign(
              # return_to: return_to,
              post_thread: nil,
              page_title: title,
              feed_name: title,
              feed: AsyncResult.loading()
            )
            |> start_async(:feed, fn ->
              case Bluesky.get_post_thread(root_uri, user, depth: 50) do
                {:ok, thread} -> Feed.decode_thread(thread, user, post_uri)
                error -> error
              end
            end)
          else
            %{feed: feed} = socket.assigns

            socket
            |> stream(:posts, [], reset: true)
            |> assign(
              # return_to: return_to,
              post_thread: nil,
              page_title: title,
              feed_name: title,
              feed: AsyncResult.failed(feed, "Missing post URI")
            )
          end

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

  def handle_event("modal-thread", %{"post_uri" => post_uri} = params, socket) do
    user = socket.assigns[:current_user]
    post_uri = Feed.decode_post_uri(post_uri)

    root_uri =
      case params["root_uri"] do
        root_uri when is_binary(root_uri) ->
          Feed.decode_post_uri(root_uri)

        _ ->
          Bluesky.resolve_root_uri(post_uri, user)
      end

    socket =
      socket
      |> start_async(:modal, fn ->
        case Bluesky.get_post_thread(root_uri, user, depth: 50) do
          {:ok, thread} -> Feed.decode_thread(thread, user, post_uri)
          error -> error
        end
      end)
      |> assign(:show_modal, true)

    {:noreply, socket}
  end

  def handle_event("modal-thread", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("modal-cancel", params, socket) do
    socket =
      socket
      |> assign(:modal, AsyncResult.loading())
      |> assign(:show_modal, false)

    socket =
      case Map.get(params, "thread_post") do
        url when is_binary(url) ->
          push_patch(socket, to: url)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:feed, {:ok, %{post: thread_post, posts: posts}}, socket) do
    socket =
      feed_result_ok(socket, posts)
      |> assign(:thread_post, SandboxWeb.post_thread_url(thread_post))

    {:noreply, socket}
  end

  def handle_async(:feed, {:ok, %{posts: posts}}, socket) do
    socket = feed_result_ok(socket, posts)
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

  def handle_async(:modal, {:ok, %{post: thread_post, posts: posts}}, socket) do
    %{modal: modal} = socket.assigns

    posts = Enum.map(posts, fn post -> {Feed.Post.stream_id(post), post} end)

    socket =
      socket
      |> assign(
        thread_post: SandboxWeb.post_thread_url(thread_post),
        modal: AsyncResult.ok(modal, %{type: :thread, posts: posts})
      )

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

  def feed_result_ok(socket, posts) do
    %{feed: feed} = socket.assigns
    count = Enum.count(posts)

    socket
    |> stream(:posts, posts)
    |> assign(:feed, AsyncResult.ok(feed, %{count: count}))
  end

  def feed_display_name(:me, user) do
    "@" <> user.handle
  end

  def feed_display_name(feed, _user) do
    Map.get(@feed_display_names, feed, "feed")
  end
end
