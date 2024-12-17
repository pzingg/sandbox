defmodule Sandbox.Bluesky.WebsocketClient do
  @moduledoc """
  A client for Bluesky Firehose (repos or labels).
  """

  use WebSockex

  require Logger

  alias Sandbox.Bluesky.{CAR, SubscribeLabels, SubscribeRepos}

  @repos_base_uri "wss://bsky.network/xrpc"
  @repos_method "com.atproto.sync.subscribeRepos"

  @labels_base_uri "wss://mod.bsky.app/xrpc"
  @labels_method "com.atproto.sync.subscribeLabels"

  def start(arg) do
    Logger.debug("start arg: #{inspect(arg)}")

    with {:ok, stream_type, url, opts} <- parse_arguments(arg) do
      WebSockex.start(url, __MODULE__, %{stream: stream_type, debug: true}, opts)
    end
  end

  def start_link(arg) do
    Logger.debug("start_link arg: #{inspect(arg)}")

    with {:ok, stream_type, url, opts} <- parse_arguments(arg) do
      WebSockex.start_link(url, __MODULE__, %{stream: stream_type, debug: true}, opts)
    end
  end

  @doc """
  Keyword arguments:
    - `:stream` - `:repos` or `:labels`
    - `:params` - optional [cursor: cursor] (an integer)
    - `:debug` - `:trace`, `:log`
  """
  def parse_arguments(arg) do
    stream_type = Keyword.get(arg, :stream)

    {_name, base_uri, method} =
      case stream_type do
        :repos -> {"FirehoseReposClient", @repos_base_uri, @repos_method}
        :labels -> {"FirehoseLabelsClient", @labels_base_uri, @labels_method}
        _ -> {nil, nil, nil}
      end

    if base_uri do
      params = Keyword.get(arg, :params)

      qs =
        if params do
          "?#{URI.encode_query(params)}"
        else
          ""
        end

      url = "#{base_uri}/#{method}#{qs}"
      opts = [async: true, handle_initial_conn_failure: true]
      debug = Keyword.get(arg, :debug)

      opts =
        if debug do
          Keyword.put(opts, :debug, debug)
        else
          opts
        end

      {:ok, stream_type, url, opts}
    else
      {:error, "invalid stream type: #{inspect(stream_type)}"}
    end
  end

  def handle_frame({:binary, msg}, %{stream: stream_type, debug: debug} = state) do
    state =
      case decode_frame(msg, stream_type) do
        {:ok, %{repo: repo} = message} ->
          post = CAR.find_post_block(message)
          log_post(post, repo)
          if debug && post do
            rev = message["rev"]
            File.write("post-commit-#{rev}.json", Jason.encode!(message, pretty: true))
            %{state | debug: false}
          else
            state
          end

        {:error, reason} ->
          Logger.error("Failed to decode a frame: #{inspect(reason)}")
          state

        _ ->
          state
      end

    {:ok, state}
  end

  def handle_frame(other, state) do
    Logger.debug("Received something else: #{inspect(other)}")
    {:ok, state}
  end

  def handle_cast({:send, {stream_type, msg} = frame}, state) do
    Logger.debug("Sending #{stream_type} frame with payload: #{msg}")
    {:reply, frame, state}
  end

  def handle_cast(other, state) do
    Logger.debug("cast something else: #{inspect(other)}")
    {:ok, state}
  end

  def handle_info(other, state) do
    Logger.debug("info something else: #{inspect(other)}")
    {:ok, state}
  end

  def handle_disconnect(%{reason: reason}, state) do
    Logger.debug("disconnect: #{inspect(reason)}")
    {:ok, state}
  end

  def terminate(reason, _state) do
    Logger.debug("Socket terminating: #{inspect(reason)}")
    :ok
  end

  @doc """
  See https://docs.bsky.app/blog/create-post
  (although "ref" has changed).

  Embed "$type"s for posts:
    - "app.bsky.embed.record" - quote post, with "record.uri" and "record.cid"
    - "app.bsky.embed.images" - images, where "images" is a list. each image is a map with
      "aspectRatio": { "height": 600, "width": 600 },
      "size": integer
      "alt": string
      "image": {
        "$type": "blob",
        "mimeType": "image/webp",
        "ref": cid
      },
    - "app.bsky.embed.video" - a video "video" is
      "$type": "blob",
      "mimeType": "video/mp4",
      "size": integer,
      "ref": cid
      },
    - "app.bsky.embed.external" - an external, where "external" is
      "uri": "https://bsky.app",
      "title": "Bluesky Social",
      "description": "See what's next.",
      "thumb": {
        "$type": "blob",
        "ref": cid,
        "mimeType": "image/png",
        "size": 23527
      }
  """

  def log_post(%{"$type": "app.bsky.feed.post"} = post, repo) do
    text = Map.get(post, :text)
    _ = Logger.debug("post in #{repo}: '#{text}'")
    reply = Map.get(post, :reply)

    if !is_nil(reply) do
      _ = Logger.debug(" ... in reply to #{reply.parent.uri}")
    end

    embed = Map.get(post, :embed)

    if !is_nil(embed) do
      case Map.get(embed, :"$type") do
        "app.bsky.embed.record" ->
          _ = Logger.debug(" ... quote post of #{embed.record.uri}")

        "app.bsky.embed.recordWithMedia" ->
          _ = Logger.debug(" ... quote post with media #{inspect(embed)}")

        "app.bsky.embed.images" ->
        _ = Logger.debug(" ... with #{Enum.count(embed.images)} images")

        "app.bsky.embed.video" ->
          _ = Logger.debug(" ... with a video")

        "app.bsky.embed.external" ->
          _ = Logger.debug(" ... with preview '#{embed.external.title}' at #{embed.external.uri}")

        other when is_binary(other) ->
          _ = Logger.debug(" ... unrecognized embed type #{inspect(embed)}")

        nil ->
          :ok
      end
    end
  end

  def log_post(%{"$type": "app.bsky.feed.repost"} = post, repo) do
    subject = Map.get(post, :subject)
    _ = Logger.debug("repost in #{repo}, of #{subject.uri}")
  end

  def log_post(_, _), do: nil

  @doc """
  Parse a frame from bytes of stream of bytes.
  Recurses to get multiple objects.
  """
  def decode_frame(data, stream_type) do
    parts = from_bytes!(data)

    case Enum.count(parts) do
      0 ->
        {:error, "invalid frame: no CBOR data"}

      1 ->
        {:error, "invalid frame: no body"}

      2 ->
        [header, body] = parts

        if is_nil(body) do
          {:error, "invalid frame: nil body"}
        else
          with {:ok, message_type} <- decode_frame_header(header, stream_type),
               {:ok, message} <- decode_frame_body(message_type, body) do
            {:ok, message}
          end
        end
    end
  end

  def decode_frame_header(%{op: 1, t: t}, stream_type) do
    message_type = message_types(stream_type) |> Map.get(t)

    if message_type do
      {:ok, message_type}
    else
      {:error, "invalid type #{inspect(t)} for stream_type #{inspect(stream_type)}"}
    end
  end

  def decode_frame_header(%{op: op, t: _t} = header, _stream_type) do
    {:error, "invalid op #{inspect(op)} in header: #{inspect(header)}"}
  end

  def decode_frame_header(header, _stream_type) do
    {:error, "invalid header: #{inspect(header)}"}
  end

  def decode_frame_body(message_type, body) do
    case message_type do
      SubscribeRepos.Commit ->
        message_type.new(body)

      _ ->
        {:error, "unimplemented message type #{message_type}"}
    end
  end

  @doc """
  Decode frame from bytes of stream of bytes.
  Recurses to get multiple objects.
  """
  def from_bytes!(data, acc \\ []) do
    {term, rest} = CAR.decode_cbor!(data)
    acc = acc ++ [term]

    if rest == "" do
      acc
    else
      from_bytes!(rest, acc)
    end
  end

  def message_types(:repos) do
    %{
      "#commit" => SubscribeRepos.Commit,
      "#handle" => SubscribeRepos.Handle,
      "#migrate" => SubscribeRepos.Migrate,
      "#tombstone" => SubscribeRepos.Tombstone,
      "#info" => SubscribeRepos.Info,
      # DEPRECATED
      "#identity" => SubscribeRepos.Identity,
      "#account" => SubscribeRepos.Account
    }
  end

  def message_types(:labels) do
    %{
      "#labels" => SubscribeLabels.Labels,
      "#info" => SubscribeLabels.Info
    }
  end
end
