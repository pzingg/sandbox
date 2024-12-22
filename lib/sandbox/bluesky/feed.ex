defmodule Sandbox.Bluesky.Feed do
  @moduledoc """
  Parsing `getTimeline` and `getPostThread` responses into
  simple maps for UI.
  """

  require Logger

  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.AtURI
  alias __MODULE__

  @type attachment_type() :: :card | :image | :video
  @type link_type() :: :tag | :mention | :uri
  @type list_type() :: :mod_list | :curate_list | :reference_list

  @type embed_type() ::
          :post
          | :blocked
          | :not_found
          | :detached
          | :images
          | :video
          | :list
          | :feed_generator
          | :starter_pack
          | :external
  @type reason_type() :: :repost | :pin
  @type post_view_type() :: :author | :blocked | :detached | :not_found

  defmodule Author do
    @moduledoc false

    @typedoc """
    `:description` is used in `Embed.feed_generator`, `BsList.creator`, and `BsListItem.subject`
    """
    @type t() :: %__MODULE__{
            did: String.t(),
            uri: String.t(),
            cid: String.t(),
            avatar: String.t() | nil,
            display_name: String.t() | nil,
            handle: String.t() | nil,
            name: String.t() | nil,
            description: String.t() | nil
          }

    @enforce_keys [:did]

    defstruct [:did, :uri, :cid, :avatar, :display_name, :handle, :name, :description]

    def hydrated?(author) do
      is_binary(author.display_name)
    end
  end

  defmodule PostInfo do
    @moduledoc false

    @type t() :: %__MODULE__{
            type: Feed.post_view_type(),
            uri: String.t(),
            author: Author.t() | nil,
            not_found: boolean(),
            blocked: boolean(),
            detached: boolean()
          }

    @enforce_keys [:type]

    defstruct [:type, :uri, :author, not_found: false, blocked: false, detached: false]
  end

  defmodule ListItem do
    @moduledoc false

    alias Feed.Author

    @type t() :: %__MODULE__{
            uri: String.t(),
            subject: Author.t()
          }

    @enforce_keys [:uri, :subject]

    defstruct [:uri, :subject]
  end

  defmodule GraphList do
    @moduledoc false

    @type t() :: %__MODULE__{
            type: Feed.list_type(),
            items: nonempty_list(Feed.ListItem.t()),
            creator: Feed.Author.t(),
            summary: Feed.Author.t()
          }

    @enforce_keys [:type, :creator, :summary]

    defstruct [:type, :items, :creator, :summary]

    def avatar_count(list) do
      min(Enum.count(list.items), 6)
    end

    def avatar_list(list) do
      Enum.take(list.items, 6)
    end

    def display_type(%{type: :mod_list}), do: "Moderation list"
    def display_type(_list), do: "User list"

    @doc """
    Convert from e.g.:

    `"at://did:plc:kjphtra6banujggchl3wcgbp/app.bsky.graph.list/3ldobu5ou372j"`

    to:

    `"https://bsky.app/profile/did:plc:kjphtra6banujggchl3wcgbp/lists/3ldobu5ou372j"`
    """
    def bsky_list_url(list) do
      case AtURI.parse(list.uri) do
        {:ok, at_uri} ->
          name = AtURI.did(at_uri)
          rkey = AtURI.rkey(at_uri)

          if name && rkey do
            "https://bsky.app/profile/#{name}/lists/#{rkey}"
          else
            list.uri
          end

        _ ->
          list.uri
      end
    end
  end

  defmodule StarterPack do
    @moduledoc false

    @type t() :: %__MODULE__{
            uri: String.t(),
            feeds: nonempty_list(Feed.FeedGenerator.t()) | nil,
            list: Feed.List.t() | nil,
            creator: Feed.Author.t(),
            name: String.t(),
            description: String.t()
          }

    @enforce_keys [:uri]

    defstruct [:uri, :feeds, :list, :creator, :name, :description]

    @doc """
    Convert from e.g.:

    `"at://did:plc:ni7kk23wfdpfeyuy465hnznu/app.bsky.graph.starterpack/3lbnf4mj77y23"`

    to:

    `"https://bsky.app/start/did:plc:ni7kk23wfdpfeyuy465hnznu/3lbnf4mj77y23"`
    """
    def bsky_start_url(pack) do
      case AtURI.parse(pack.uri) do
        {:ok, at_uri} ->
          name = AtURI.did(at_uri)
          rkey = AtURI.rkey(at_uri)

          if name && rkey do
            "https://bsky.app/start/#{name}/#{rkey}"
          else
            pack.uri
          end

        _ ->
          pack.uri
      end
    end

    @doc """
    Convert from e.g.:

    `"at://did:plc:ni7kk23wfdpfeyuy465hnznu/app.bsky.graph.starterpack/3lbnf4mj77y23"`

    to:

    `"https://bsky.app/starter-pack/did:plc:ni7kk23wfdpfeyuy465hnznu/3lbnf4mj77y23"`
    """
    def bsky_starter_pack_url(pack) do
      case AtURI.parse(pack.uri) do
        {:ok, at_uri} ->
          name = AtURI.did(at_uri)
          rkey = AtURI.rkey(at_uri)

          if name && rkey do
            "https://bsky.app/starter-pack/#{name}/#{rkey}"
          else
            pack.uri
          end

        _ ->
          pack.uri
      end
    end
  end

  defmodule FeedGenerator do
    @moduledoc false

    @type t() :: %__MODULE__{
            creator: Author.t(),
            summary: Author.t()
          }

    @enforce_keys [:creator, :summary]

    defstruct [:creator, :summary]
  end

  defmodule Link do
    @moduledoc false

    alias Feed.Author

    @type t() :: %__MODULE__{
            type: Feed.link_type(),
            title: String.t(),
            byte_start: integer(),
            byte_end: integer(),
            uri: String.t() | nil,
            tag: String.t() | nil,
            mention: Author.t() | nil
          }

    @enforce_keys [:type, :byte_start, :byte_end]

    defstruct [:type, :byte_start, :byte_end, :title, :uri, :tag, :mention]

    def hydrated?(link) do
      link.type != :mention || Author.hydrated?(link.mention)
    end

    def sort(links) do
      Enum.sort_by(links, & &1, &link_sorter/2)
    end

    defp link_sorter(a, b), do: a.byte_start < b.byte_start
  end

  defmodule Attachment do
    @moduledoc false

    @type t() :: %__MODULE__{
            type: Feed.attachment_type(),
            cid: String.t() | nil,
            uri: String.t() | nil,
            height: integer() | nil,
            width: integer() | nil,
            aspect: integer(),
            instance: integer(),
            alt: String.t() | nil,
            source: String.t() | nil,
            thumb: String.t() | nil,
            title: String.t() | nil,
            domain: String.t() | nil,
            description: String.t() | nil
          }

    @enforce_keys [:type]

    defstruct [
      :type,
      :cid,
      :uri,
      :height,
      :width,
      :alt,
      :source,
      :thumb,
      :title,
      :domain,
      :description,
      aspect: 0,
      instance: 0
    ]

    def hydrated?(%{type: :image} = att) do
      is_binary(att.thumb)
    end

    def hydrated?(%{type: :video} = att) do
      is_binary(att.thumb)
    end

    def hydrated?(%{type: :post} = att) do
      !is_nil(att.post)
    end

    def alt(att) do
      cond do
        is_binary(att.alt) && att.alt != "" ->
          att.alt

        is_binary(att.title) && att.title != "" ->
          String.slice(att.title, 0, 30)

        true ->
          nil
      end
    end

    def set_instance(att) do
      case Cachex.incr(:bluesky, "autoinc") do
        {:ok, instance} ->
          %__MODULE__{att | instance: instance}

        {:error, reason} ->
          Logger.error("Failed to get autoinc #{reason}")
          %__MODULE__{att | instance: 1}
      end
    end
  end

  defmodule Embed do
    @moduledoc """
    `:creator` and `:summary` fields are for the `:feed_generator` and `:list` types
    `:post` is a `PostInfo` for `:not_found`, `:blocked`, and `:detached` types
    """

    @type t() :: %__MODULE__{
            type: Feed.embed_type(),
            title: String.t() | nil,
            post: Feed.Post.t() | Feed.PostInfo.t() | nil,
            external: Feed.Attachment.t(),
            images: nonempty_list(Feed.Attachment.t()) | nil,
            video: Feed.Attachment.t() | nil,
            list: Feed.List.t() | nil,
            feed_generator: Feed.FeedGenerator.t() | nil,
            starter_pack: Feed.StarterPack.t() | nil
          }

    @enforce_keys [:type]

    defstruct [
      :type,
      :title,
      :post,
      :external,
      :images,
      :video,
      :list,
      :feed_generator,
      :starter_pack
    ]

    def hydrated?(%{type: :post} = embed) do
      Attachment.hydrated?(embed.external)
    end

    def hydrated?(%{type: :video} = embed) do
      Attachment.hydrated?(embed.video)
    end

    def hydrated?(%{type: :images} = embed) do
      Enum.all?(embed.images, &Attachment.hydrated?(&1))
    end
  end

  defmodule Reason do
    @moduledoc false

    alias Sandbox.Bluesky.Feed

    @type t() :: %__MODULE__{
            type: Feed.reason_type(),
            by: Author.t(),
            date: DateTime.t() | nil
          }

    @enforce_keys [:type, :by, :date]

    defstruct [:type, :by, :date]
  end

  defmodule Post do
    @moduledoc false

    @type t() :: %__MODULE__{
            uri: String.t(),
            encoded_uri: String.t(),
            cid: String.t(),
            text: String.t(),
            date: DateTime.t() | nil,
            author: Author.t() | nil,
            instance: integer(),
            reply_parent: PostInfo.t() | nil,
            reason: Reason.t() | nil,
            embeds: nonempty_list(Embed.t()) | nil,
            links: nonempty_list(Link.t()) | nil
          }

    @enforce_keys [:uri, :encoded_uri]

    defstruct [
      :uri,
      :encoded_uri,
      :cid,
      :text,
      :date,
      :author,
      :reply_parent,
      :reason,
      :embeds,
      :links,
      instance: 0
    ]

    def ref?(post) do
      is_nil(post.cid)
    end

    def hydrated?(post) do
      is_binary(post.date)
    end

    def set_instance(post) do
      case Cachex.incr(:bluesky, "autoinc") do
        {:ok, instance} ->
          %__MODULE__{post | instance: instance}

        _ ->
          post
      end
    end

    def repost?(post), do: is_map(post.reason) && post.reason.type == :repost

    def reply?(post), do: is_map(post.reply_parent)

    def has_images?(post), do: find_embed(post, :images) |> is_map()

    def images(post), do: find_embed(post, :images) |> Map.get(:images)

    def has_video?(post), do: find_embed(post, :video) |> is_map()

    def video(post), do: find_embed(post, :video) |> Map.get(:video)

    def has_external?(post), do: find_embed(post, :external) |> is_map()

    def external(post), do: find_embed(post, :external) |> Map.get(:external)

    def quote_post?(post), do: find_embed(post, :post) |> is_map()

    def quoted_post(post), do: find_embed(post, :post) |> Map.get(:post)

    def has_feed_generator?(post), do: find_embed(post, :feed_generator) |> is_map()

    def feed_generator(post), do: find_embed(post, :feed_generator) |> Map.get(:feed_generator)

    def has_list?(post), do: find_embed(post, :list) |> is_map()

    def list(post), do: find_embed(post, :list) |> Map.get(:list)

    def has_starter_pack?(post), do: find_embed(post, :starter_pack) |> is_map()

    def starter_pack(post), do: find_embed(post, :starter_pack) |> Map.get(:starter_pack)

    defp find_embed(%{embeds: [_ | _] = embeds}, type) do
      Enum.find(embeds, fn embed -> embed.type == type end)
    end

    defp find_embed(_, _), do: nil

    def stream_id(post), do: stream_id(post, "posts-")

    def stream_id(post, prefix), do: Bluesky.uri_to_id(post.uri, prefix, post.instance)
  end

  @doc """
  Decodes all the items returned from `getAuthorFeed` or `getTimeline`.
  """
  def decode_feed(%{"feed" => feed}, auth) do
    # Reset instance counter
    Cachex.put(:bluesky, "autoinc", 0)

    posts =
      feed
      |> Enum.map(&decode_post(&1, auth))
      |> Enum.filter(fn post -> !is_nil(post) end)
      |> Enum.map(&Post.set_instance/1)

    {:ok, posts}
  end

  def decode_feed(_feed, _auth), do: {:error, "No feed in response"}

  @doc """
  Decodes a post as returned from `getPostThread` and all its ancestors.
  """
  def decode_thread(%{"thread" => thread}, auth) do
    ancestors = decode_thread_ancestors(thread, auth, [])
    post = decode_post(thread, auth)
    posts = Enum.reverse([post | ancestors]) |> Bluesky.nil_if_emptylist()
    {:ok, posts}
  end

  def decode_thread(_thread, _auth), do: {:error, "No thread in response"}

  def decode_thread_ancestors(post_or_thread, auth, acc) do
    case Map.get(post_or_thread, "parent") do
      nil ->
        acc

      parent when is_map(parent) ->
        parent_post = decode_post(parent, auth)
        decode_thread_ancestors(parent, auth, [parent_post | acc])

      other ->
        Logger.error("Thread parent is not a map #{inspect(other)}")
        acc
    end
  end

  @doc """
  Decodes a post with its reply and reason.

  This is the top-level entrypoint for either the `"thread"` in the response
  from a `getPostThread` xrpc call, or for an item from the items returned by
  `getAuthorFeed` or `getTimeline`.
  """
  def decode_post(%{"post" => %{"record" => record} = post} = item, auth) when is_map(record) do
    # This is from `getAuthorFeed` or `getTimeline`, each post has a `"record"`
    # with a `"$type"` specifier
    case record["$type"] do
      nil ->
        Logger.error("No $type in post record '#{inspect(record)}'")
        nil

      "app.bsky.feed.post" ->
        decode_post(post, item["reply"], item["reason"], auth)

      other ->
        Logger.error("Unknown post record type '#{other}'")
        nil
    end
  end

  def decode_post(%{"post" => post, "$type" => ptype} = item, auth) do
    # This is from `getPostThread`, each parent has a `"$type"` specifier
    case ptype do
      nil ->
        Logger.error("No $type in thread item '#{item}'")
        nil

      "app.bsky.feed.defs#threadViewPost" ->
        decode_post(post, item["reply"], item["reason"], auth)

      "app.bsky.feed.defs#blockedPost" ->
        build_post_info(post, auth)

      "app.bsky.feed.defs#notFoundPost" ->
        build_post_info(post, auth)

      _ ->
        Logger.error("Unknown thread post type '#{ptype}'")
        nil
    end
  end

  @doc """
  Decodes a post with its reply and reason.
  """
  @spec decode_post(map(), map() | nil, map() | nil, Bluesky.auth()) :: Feed.Post.t() | nil
  def decode_post(%{"uri" => _, "cid" => _} = post, reply, reason, auth) do
    build_post(post, reply, reason, auth)
  end

  def decode_post(post, _reply, _reason, _auth) do
    Logger.error("Mising uri or cid in post #{inspect(post)}")
    nil
  end

  def build_post(%{"uri" => uri} = post, reply, reason, auth) do
    record = record_or_value(post, post)

    embeds =
      cond do
        Map.has_key?(post, "embed") ->
          # For top-level post
          case build_embed(post["embed"], auth) do
            %Embed{} = embed ->
              [embed]

            _ ->
              nil
          end

        Map.has_key?(post, "embeds") ->
          # For embedded post
          post["embeds"]
          |> Enum.map(fn embed ->
            build_embed(embed, auth)
          end)
          |> Enum.filter(fn
            %Embed{} -> true
            _ -> false
          end)

        true ->
          nil
      end

    links =
      Map.get(record, "facets", [])
      |> Enum.flat_map(fn facet ->
        byte_start = get_in(facet, ["index", "byteStart"])
        byte_end = get_in(facet, ["index", "byteEnd"])

        Map.get(facet, "features", [])
        |> Enum.map(fn feature ->
          {_, ftype} = split_type(feature["$type"])

          case ftype do
            nil ->
              Logger.error("No $type for feature #{inspect(feature)}")
              nil

            "link" ->
              link_uri = feature["uri"]
              domain = Bluesky.get_origin(link_uri)

              %Link{
                type: :uri,
                byte_start: byte_start,
                byte_end: byte_end,
                uri: link_uri,
                title: domain
              }

            "tag" ->
              tag = feature["tag"]
              %Link{type: :tag, byte_start: byte_start, byte_end: byte_end, tag: tag, title: tag}

            "mention" ->
              mention = %Author{did: feature["did"]}
              %Link{type: :mention, byte_start: byte_start, byte_end: byte_end, mention: mention}

            _ ->
              Logger.error("Unhandled facet type '#{feature["$type"]}'")
              nil
          end
        end)
      end)
      |> Enum.filter(fn link -> !is_nil(link) end)

    %Post{
      uri: uri,
      encoded_uri: SandboxWeb.encode_post_uri(uri),
      cid: post["cid"],
      author: build_author(post["author"], auth),
      date: Bluesky.to_date(record["createdAt"]),
      text: record["text"],
      reason: get_reason(reason, auth),
      reply_parent: build_post_info(reply["parent"], auth),
      embeds: Bluesky.nil_if_emptylist(embeds),
      links: Bluesky.nil_if_emptylist(links)
    }
  end

  def build_post(post, _reply, _reason, _auth) do
    Logger.error("No uri in post #{inspect(post)}")
    nil
  end

  def get_reason(reason, auth) when is_map(reason) do
    {_, fragment} = split_type(reason["$type"])

    case fragment do
      nil ->
        nil

      "reasonRepost" ->
        %Reason{
          type: :repost,
          by: build_author(reason["by"], auth),
          date: Bluesky.to_date(reason["indexedAt"])
        }

      "reasonPin" ->
        %Reason{
          type: :pin,
          by: build_author(reason["by"], auth),
          date: Bluesky.to_date(reason["indexedAt"])
        }

      _ ->
        Logger.error("Unknown reason type '#{reason["$type"]}'")
        nil
    end
  end

  def get_reason(_, _), do: nil

  def build_embed(embed, auth) do
    case embed["$type"] do
      nil ->
        Logger.error("No $type for embed #{inspect(embed)}")
        nil

      # Case 1: Image
      "app.bsky.embed.images#view" ->
        build_attachment_embed(:images, embed["images"])

      # Case 2: External link
      "app.bsky.embed.external#view" ->
        build_attachment_embed(:external, embed["external"])

      # Case 3: Record (quote or linked post)
      "app.bsky.embed.record#view" ->
        # File.write("embed-record.json", Jason.encode!(post, pretty: true))
        quoted_embed(embed, nil, auth)

      # Case 4: Video
      "app.bsky.embed.video#view" ->
        build_attachment_embed(:video, embed)

      # Case 5: Record with media
      "app.bsky.embed.recordWithMedia#view" ->
        record = embed["record"]
        media = embed["media"]
        quoted_embed(record, media, auth)

      etype ->
        Logger.error("Unhandled embed type '#{etype}'")
        nil
    end
  end

  def quoted_embed(embed, media, auth) do
    record = embed["record"]

    case record["$type"] do
      nil ->
        Logger.error("No $type for embed record #{inspect(record)}")
        nil

      # Case 3.1: Post
      "app.bsky.embed.record#viewRecord" ->
        embed_post(record, media, auth)

      # Case 3.2: List
      "app.bsky.graph.defs#listView" ->
        list = resolve_list(record["uri"], auth, record)

        %Embed{
          type: :list,
          list: list
        }

      # Case 3.3: Feed
      "app.bsky.feed.defs#generatorView" ->
        embed_feed_generator(record, auth)

      # Case 3.4: Labeler
      "app.bsky.labeler.defs#labelerView" ->
        nil

      # Case 3.5: Starter pack
      "app.bsky.graph.defs#starterPackViewBasic" ->
        embed_starter_pack(record, auth)

      # Case 3.6: Post not found
      "app.bsky.embed.record#viewNotFound" ->
        post_info = build_post_info(record, auth)

        %Embed{
          type: :not_found,
          post: post_info,
          title: "Quoted post not found, it may have been deleted."
        }

      # Case 3.7: Post blocked
      "app.bsky.embed.record#viewBlocked" ->
        post_info = build_post_info(record, auth)

        %Embed{
          type: :blocked,
          post: post_info,
          title: "The quoted post is blocked."
        }

      # Case 3.8: Detached quote post
      "app.bsky.embed.record#viewDetached" ->
        nil

      _ ->
        Logger.error("Unhandled embed record type '#{record["$type"]}'")
        nil
    end
  end

  def embed_post(post, media, auth) do
    post = build_post(post, nil, nil, auth)

    {media, title} =
      if is_map(media) do
        case media["$type"] do
          nil ->
            Logger.error("No $type for embedded media")
            {nil, "\"Post\""}

          "app.bsky.embed.images#view" ->
            {[build_attachment_embed(:images, media["images"])], "\"Post with images\""}

          "app.bsky.embed.external#view" ->
            {[build_attachment_embed(:external, media["external"])], "\"Post with preview\""}

          "app.bsky.embed.video#view" ->
            Logger.error("in embed_post video#view, media: #{inspect(media)}")
            {[build_attachment_embed(:video, media["video"])], "\"Post with video\""}

          etype ->
            Logger.error("Unhandled media $type '#{etype}'")
            {nil, "\"Post\""}
        end
      else
        {nil, "\"Post\""}
      end

    post =
      if is_list(media) do
        case post.embeds do
          [_ | _] -> %Post{post | embeds: post.embeds ++ media}
          _ -> %Post{post | embeds: media}
        end
      else
        post
      end

    %Embed{type: :post, post: post, title: title}
  end

  def build_attachment_embed(:images, media) do
    images = build_attachments(:image, media)

    if is_nil(images) do
      nil
    else
      %Embed{
        type: :images,
        images: images
      }
    end
  end

  def build_attachment_embed(:video, media) do
    video = build_attachment(:video, media)

    if is_nil(video) do
      nil
    else
      %Embed{
        type: :video,
        video: video
      }
    end
  end

  def build_attachment_embed(:external, media) do
    external = build_attachment(:card, media)

    if is_nil(external) do
      nil
    else
      %Embed{
        type: :external,
        external: external
      }
    end
  end

  def build_attachments(type, media) when is_list(media) do
    media
    |> Enum.map(&build_attachment(type, &1))
    |> Bluesky.nil_if_emptylist()
  end

  def build_attachments(type, media) do
    Logger.error("build_attachments #{type} not a list #{inspect(media)}")
    nil
  end

  def build_attachment(type, att) when not is_map(att) do
    Logger.error("No data for #{type} attachment #{inspect(att)}")
    nil
  end

  def build_attachment(:card, %{"uri" => uri} = att) do
    %Attachment{
      type: :card,
      uri: uri,
      thumb: att["thumb"],
      title: Bluesky.nil_if_empty(att["title"]),
      domain: Bluesky.get_domain(uri, level: 2),
      description: Bluesky.nil_if_empty(att["description"])
    }
    |> Attachment.set_instance()
  end

  def build_attachment(:image, %{"thumb" => thumb} = att) do
    {width, height, aspect} = get_aspect(att)

    %Attachment{
      type: :image,
      cid: att["cid"],
      height: height,
      width: width,
      aspect: aspect,
      alt: att["alt"],
      thumb: thumb
    }
    |> Attachment.set_instance()
  end

  def build_attachment(:video, %{"playlist" => source} = att) do
    {width, height, aspect} = get_aspect(att)

    %Attachment{
      type: :video,
      cid: att["cid"],
      height: height,
      width: width,
      aspect: aspect,
      alt: att["alt"],
      source: source,
      thumb: att["thumbnail"]
    }
    |> Attachment.set_instance()
  end

  def build_attachment(type, att) do
    Logger.error("attachment type #{type} missing required attributes #{inspect(att)}")
    nil
  end

  def get_aspect(att) do
    height = att["aspectRatio"]["height"]
    width = att["aspectRatio"]["width"]

    if is_number(height) && is_number(width) &&
         height > 0 && width > 0 &&
         height / width > 0.8 do
      {height, width, 1}
    else
      {height, width, 0}
    end
  end

  def embed_feed_generator(feed, auth) do
    feed_gen = %FeedGenerator{
      creator: build_author(feed["creator"], auth),
      summary: build_author(feed, auth)
    }

    %Embed{
      type: :feed_generator,
      feed_generator: feed_gen,
      title: "\"Feed\""
    }
  end

  def embed_starter_pack(pack, auth) do
    record = pack["record"]

    feeds =
      record["feeds"]
      |> Enum.map(fn feed ->
        %FeedGenerator{
          creator: build_author(feed["creator"], auth),
          summary: build_author(feed, auth)
        }
      end)

    starter_pack = %StarterPack{
      uri: pack["uri"],
      feeds: feeds,
      list: resolve_list(record["list"], auth),
      creator: build_author(pack["creator"], auth),
      name: record["name"],
      description: record["description"]
    }

    %Embed{
      type: :starter_pack,
      starter_pack: starter_pack,
      title: "\"Starter Pack\""
    }
  end

  @doc """
  Fetches the items in a list, given the list's at-uri.

  If the fetch fails, and the `list` argument is given,
  fall back to a list with no items.
  """
  def resolve_list(uri, auth, list \\ nil) do
    case Bluesky.get_list(auth, uri) do
      {:ok, body} ->
        build_list(body["list"], body["items"], auth)

      {:error, reason} ->
        Logger.error("Failed to fetch list #{reason}")

        if is_nil(list) do
          nil
        else
          build_list(list, [], auth)
        end
    end
  end

  def build_list(%{"purpose" => purpose} = list, items, auth) when is_list(items) do
    {_, ltype} = split_type(purpose)

    if is_binary(ltype) do
      ltype =
        ltype
        |> String.split(".")
        |> List.last()
        |> String.replace_trailing("list", "_list")
        |> String.to_atom()

      items = Enum.map(items, &build_list_item(&1, auth))

      %GraphList{
        type: ltype,
        items: Bluesky.nil_if_emptylist(items),
        creator: build_author(list["creator"], auth),
        summary: build_author(list, auth)
      }
    else
      nil
    end
  end

  def build_list(list, items, _auth) do
    Logger.error("No purpose in list or items is not a list")
    Logger.error(" -> list #{inspect(list)}")
    Logger.error(" -> items #{inspect(items)}")
    nil
  end

  def build_list_item(%{"uri" => uri, "subject" => subject}, auth) do
    %ListItem{uri: uri, subject: build_author(subject, auth)}
  end

  def build_list_item(item, _) do
    Logger.error("Invalid list item #{inspect(item)}")
    nil
  end

  @post_info_types %{
    "app.bsky.feed.defs#postView" => [type: :author],
    "app.bsky.feed.defs#blockedPost" => [type: :blocked, blocke: true],
    "app.bsky.feed.defs#notFoundPost" => [type: :not_found, not_found: true],
    "app.bsky.embed.record#viewBlocked" => [type: :blocked, blocked: true],
    "app.bsky.embed.record#viewNotFound" => [type: :not_found, not_found: true],
    "app.bsky.embed.record#viewDetached" => [type: :detached, detached: true]
  }

  def build_post_info(nil, _auth), do: nil

  def build_post_info(%{"$type" => rtype} = record, auth) do
    case Map.get(@post_info_types, rtype) do
      nil ->
        Logger.error("Unknown post type '#{rtype}'")
        nil

      opts ->
        opts =
          Keyword.merge(opts, uri: record["uri"], author: build_author(record["author"], auth))

        struct(PostInfo, opts)
    end
  end

  def build_post_info(record, _auth) do
    Logger.error("No $type for post #{inspect(record)}")
    nil
  end

  def build_author(%{"did" => did} = author, auth) do
    # For users
    author = Bluesky.try_resolve_author(author, auth)

    %Author{
      did: did,
      uri: author["uri"],
      cid: author["cid"],
      handle: author["handle"],
      avatar: author["avatar"],
      display_name: Map.get(author, "displayName", did),
      name: author["name"],
      description: author["description"]
    }
  end

  def build_author(%{"uri" => uri} = author, _) do
    # For list summary, etc.
    %Author{
      did: nil,
      uri: uri,
      cid: author["cid"],
      handle: author["handle"],
      avatar: author["avatar"],
      display_name: author["displayName"],
      name: author["name"],
      description: author["description"]
    }
  end

  def build_author(%{} = author, _) do
    # No did or uri
    Logger.error("No did or uri for author #{inspect(author)}")
    nil
  end

  def build_author(_, _), do: nil

  def split_type(type) when is_binary(type) do
    case String.split(type, "#", parts: 2) do
      [t] -> {t, nil}
      [t, f] -> {t, f}
    end
  end

  def split_type(_), do: {nil, nil}

  def record_or_value(post, default \\ nil)
  def record_or_value(%{"record" => record}, _default) when is_map(record), do: record
  def record_or_value(%{"value" => record}, _default) when is_map(record), do: record
  def record_or_value(_post, default), do: default

  def link_spans(text, nil), do: [{text, nil}]
  def link_spans(text, []), do: [{text, nil}]

  def link_spans(text, links) do
    spans =
      links
      |> Link.sort()
      |> Enum.reduce([], fn link, acc -> interval(link, acc, text) end)

    {_, %Link{byte_end: last_end}} = hd(spans)

    maybe_prepend(spans, text, last_end, byte_size(text))
    |> Enum.reverse()
  end

  defp interval(%Link{byte_start: byte_start, byte_end: byte_end} = link, acc, text) do
    last_end =
      case acc do
        [] -> 0
        [{_, link} | _] -> link.byte_end
      end

    acc = maybe_prepend(acc, text, last_end, byte_start)
    val = {:binary.part(text, byte_start, byte_end - byte_start), link}
    [val | acc]
  end

  defp maybe_prepend(acc, text, last_end, byte_start) when byte_start > last_end do
    length = byte_start - last_end
    val = {:binary.part(text, last_end, length), nil}
    [val | acc]
  end

  defp maybe_prepend(acc, _, _, _), do: acc

  def display_name(at_uri, auth) do
    case AtURI.parse(at_uri) do
      {:ok, %{host: "did:" <> _rest = did}} ->
        case Bluesky.get_profile(did, auth) do
          {:ok, %{"displayName" => display_name}} -> display_name
          _ -> did
        end

      _ ->
        at_uri
    end
  end
end
