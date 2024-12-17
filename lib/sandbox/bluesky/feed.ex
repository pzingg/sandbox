defmodule Sandbox.Bluesky.Feed do
  @moduledoc """
  Parsing `getTimeline` and `getPostThread` responses into
  simple maps for UI.
  """

  require Logger

  alias Sandbox.Bluesky
  alias __MODULE__

  @type attachment_type() :: :card | :image | :video
  @type list_type() :: :mod | :curate | :reference
  @type link_type() :: :tag | :mention | :uri
  @type embed_type() ::
          :post
          | :images
          | :video
          | :list
          | :feed_generator
          | :external
  @type reason_type() :: :repost
  @type reply_parent_type() :: :author | :blocked | :not_found

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
            description: String.t() | nil
          }

    @enforce_keys [:did]

    defstruct [:did, :uri, :cid, :avatar, :display_name, :handle, :description]

    def hydrated?(author) do
      is_binary(author.display_name)
    end
  end

  defmodule Reply do
    @moduledoc false

    @type t() :: %__MODULE__{
            type: Feed.reply_parent_type(),
            uri: String.t(),
            author: Author.t() | nil,
            not_found: boolean(),
            blocked: boolean()
          }

    @enforce_keys [:type]

    defstruct [:type, :uri, :author, not_found: false, blocked: false]
  end

  defmodule BsListItem do
    @moduledoc false

    alias Feed.Author

    @type t() :: %__MODULE__{
            uri: String.t(),
            subject: Author.t()
          }

    @enforce_keys [:uri, :subject]

    defstruct [:uri, :subject]
  end

  defmodule BsList do
    @moduledoc false

    alias Feed.Author

    @type t() :: %__MODULE__{
            type: Feed.list_type(),
            items: [BsListItem.t()]
          }

    @enforce_keys [:type, :items]

    defstruct [:type, :items]
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
      :description
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
  end

  defmodule Embed do
    @moduledoc """
    `:creator` and `:summary` fields are for the `:feed_generator` and `:list` types
    """

    @type t() :: %__MODULE__{
            type: Feed.embed_type(),
            head: String.t(),
            title: String.t() | nil,
            post: Feed.Post.t() | nil,
            list: Feed.BsList.t() | nil,
            external: Attachment.t(),
            images: nonempty_list(Attachment.t()) | nil,
            video: Attachment.t() | nil,
            creator: Author.t() | nil,
            summary: Author.t() | nil
          }

    @enforce_keys [:type, :head]

    defstruct [
      :type,
      :head,
      :title,
      :post,
      :list,
      :external,
      :images,
      :video,
      :creator,
      :summary
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
            cid: String.t(),
            text: String.t(),
            date: DateTime.t() | nil,
            author: Author.t() | nil,
            reply_parent: Author.t() | nil,
            reason: Reason.t() | nil,
            embeds: nonempty_list(Embed.t()) | nil,
            links: nonempty_list(Link.t()) | nil
          }

    @enforce_keys [:uri]

    defstruct [
      :uri,
      :cid,
      :text,
      :date,
      :author,
      :reply_parent,
      :reason,
      :embeds,
      :links
    ]

    def ref?(post) do
      is_nil(post.cid)
    end

    def hydrated?(post) do
      is_binary(post.date)
    end

    def repost?(post) do
      is_map(post.reason) && post.reason.type == :repost
    end

    def reply?(post) do
      is_map(post.reply_parent)
    end

    def has_images?(post), do: find_embed(post, :images) |> is_map()

    def images(post), do: find_embed(post, :images) |> Map.get(:images)

    def has_video?(post), do: find_embed(post, :video) |> is_map()

    def video(post), do: find_embed(post, :video) |> Map.get(:video)

    def has_external?(post), do: find_embed(post, :external) |> is_map()

    def external(post), do: find_embed(post, :external) |> Map.get(:external)

    def quote_post?(post), do: find_embed(post, :post) |> is_map()

    def quoted_post(post), do: find_embed(post, :post) |> Map.get(:post)

    def has_feed_generator?(post), do: find_embed(post, :feed_generator) |> is_map()

    def feed_generator(post) do
      find_embed(post, :feed_generator)
      |> Map.take([:summary, :creator])
    end

    defp find_embed(%{embeds: [_ | _] = embeds}, type) do
      Enum.find(embeds, fn embed -> embed.type == type end)
    end

    defp find_embed(_, _), do: nil
  end

  def posts_stream_id(post) do
    uri =
      post.uri
      |> String.replace_leading("at://", "")

    uri = Regex.replace(~r/[^-_%.:A-Za-z0-9]/, uri, "-")
    "posts-#{uri}"
  end

  def decode_feed(%{"feed" => feed}, auth) do
    posts =
      feed
      |> Enum.map(&decode_post(&1, auth))
      |> Enum.filter(fn post -> !is_nil(post) end)

    {:ok, posts}
  end

  def decode_feed(_timeline), do: {:error, "No feed in timeline"}

  def decode_post(%{"post" => post} = item, auth) do
    decode_post(post, item["reply"], item["reason"], auth)
  end

  def decode_post(%{"uri" => _, "cid" => _} = post, reply, reason, auth) do
    build_post(post, reply, reason, auth)
  end

  def decode_post(post, _auth, _in_thread?) do
    Logger.error("Mising uri or cid in post #{inspect(post)}")
    nil
  end

  def decode_post_thread(uri, auth) do
    case Bluesky.get_post_thread(uri, auth) do
      {:ok, %{"thread" => thread}} ->
        case thread["$type"] do
          "app.bsky.feed.defs#threadViewPost" ->
            build_post(thread["post"], thread["reply"], thread["reason"], auth)

          "app.bsky.feed.defs#blockedPost" ->
            build_blocked(thread, auth)

          "app.bsky.feed.defs#notFoundPost" ->
            build_not_found(thread, auth)

          type ->
            Logger.error("Unknown thread type '#{type}'")
            nil
        end

      {:error, reason} ->
        Logger.error("decode_post_thread #{uri} failed #{inspect(reason)}")
        nil
    end
  end

  def build_post(post, reply, reason, auth) do
    record = record_or_value(post, post)

    embeds =
      cond do
        Map.has_key?(post, "embed") ->
          # For top-level post
          case build_embed(post["embed"], auth) do
            %Embed{} = embed -> [embed]
            _ -> nil
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
              uri = feature["uri"]
              domain = Bluesky.get_origin(uri)

              %Link{
                type: :uri,
                byte_start: byte_start,
                byte_end: byte_end,
                uri: uri,
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
      uri: post["uri"],
      cid: post["cid"],
      author: build_author(post["author"], auth),
      date: to_date(record["createdAt"]),
      text: record["text"],
      reason: get_reason(reason, auth),
      reply_parent: get_reply_parent(reply["parent"], auth),
      embeds: nil_if_emptylist(embeds),
      links: nil_if_emptylist(links)
    }
  end

  def nil_if_emptylist([_ | _] = list), do: list
  def nil_if_emptylist(_), do: nil

  def get_reply_parent(%{"$type" => reply_type} = reply_parent, auth) do
    case reply_type do
      "app.bsky.feed.defs#postView" ->
        build_reply(reply_parent, auth)

      "app.bsky.feed.defs#blockedPost" ->
        build_blocked(reply_parent, auth)

      "app.bsky.feed.defs#notFoundPost" ->
        build_not_found(reply_parent, auth)

      reply_type ->
        Logger.error("Unknown reply parent type '#{reply_type}'")
        nil
    end
  end

  def get_reply_parent(_, _), do: {nil, nil}

  def build_reply(post, auth) do
    # $type is "app.bsky.feed.defs#postView" ->
    %Reply{
      type: :author,
      uri: post["uri"],
      author: build_author(post["author"], auth)
    }
  end

  def build_blocked(post, auth) do
    # $type is "app.bsky.feed.defs#blockedPost"
    # post["blocked"]

    %Reply{
      type: :blocked,
      uri: post["uri"],
      author: build_author(post["author"], auth),
      blocked: true
    }
  end

  def build_not_found(post, _auth) do
    # $type is "app.bsky.feed.defs#notFoundPost"
    # post["notFound"]

    %Reply{
      type: :not_found,
      uri: post["uri"],
      not_found: true
    }
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
          date: to_date(reason["indexedAt"])
        }

      _ ->
        Logger.error("Unknown reason type '#{reason["$type"]}'")
        nil
    end
  end

  def get_reason(_, _), do: nil

  defp build_embed(embed, auth) do
    {etype, _fragment} = split_type(embed["$type"])

    case etype do
      nil ->
        Logger.error("No $type for embed #{inspect(embed)}")
        nil

      "app.bsky.embed.record" ->
        # record = embed["record"]
        # File.write("embed-record.json", Jason.encode!(post, pretty: true))
        quoted_embed("Quote:", embed, nil, auth)

      "app.bsky.embed.recordWithMedia" ->
        record = embed["record"]
        media = embed["media"]
        quoted_embed("Quote with media:", record, media, auth)

      "app.bsky.embed.images" ->
        images = build_attachments(:image, embed["images"])
        count = Enum.count(images)

        head =
          case count do
            1 -> "1 image"
            _ -> "#{count} images"
          end

        %Embed{
          type: :images,
          head: head,
          images: images
        }

      "app.bsky.embed.video" ->
        %Embed{
          type: :video,
          head: "Video",
          video: build_attachment(:video, embed)
        }

      "app.bsky.embed.external" ->
        # File.write("embed-external.json", Jason.encode!(post, pretty: true))
        uri = embed["external"]["uri"]

        external = %Attachment{
          type: :card,
          uri: uri,
          thumb: embed["external"]["thumb"],
          title: embed["external"]["title"],
          domain: Bluesky.get_domain(uri, level: 2),
          description: embed["external"]["description"]
        }

        %Embed{
          type: :external,
          head: "Preview:",
          external: external
        }

      _ ->
        Logger.error("Unhandled embed type '#{embed["$type"]}'")
        nil
    end
  end

  def build_attachments(type, atts) do
    Enum.map(atts, &build_attachment(type, &1))
  end

  def build_attachment(type, att) do
    {source, thumb} =
      case type do
        :video -> {att["playlist"], att["thumbnail"]}
        _ -> {nil, att["thumb"]}
      end

    ref_type = Atom.to_string(type)

    %Attachment{
      type: type,
      height: att["aspectRatio"]["height"],
      width: att["aspectRatio"]["width"],
      alt: att["alt"],
      source: source,
      thumb: thumb,
      cid: get_in(att, [ref_type, "ref", "$link"])
    }
  end

  # TODO "quoted by xxxx"
  def quoted_embed(head, record, media, auth) do
    embed_record = record_or_value(record, record)

    case split_type(embed_record["$type"]) do
      {"app.bsky.embed.record", "viewRecord"} ->
        embed_post(head, embed_record, media, auth)

      {"app.bsky.feed.post", _} ->
        embed_post(head, embed_record, media, auth)

      {_, "generatorView"} ->
        embed_feed_generator(head, embed_record, media, auth)

      {_, "listView"} ->
        embed_list(head, embed_record, media, auth)

      _ ->
        Logger.error("Unhandled record type '#{embed_record["$type"]}'")
        nil
    end
  end

  def embed_post(head, post, media, auth) do
    post = build_post(post, nil, nil, auth)

    if is_map(media) do
      case split_type(media["$type"]) do
        {"app.bsky.embed.images", _} ->
          images = media["images"]

          %Embed{
            type: :post_images,
            head: head,
            post: post,
            title: "\"Post\"",
            images: build_attachments(:image, images)
          }

        {"app.bsky.embed.video", _} ->
          video = media["video"]

          %Embed{
            type: :post_video,
            head: head,
            post: post,
            title: "\"Post\"",
            video: build_attachment(:video, video)
          }

        {etype, _} ->
          etype = "post_#{etype}"
          %Embed{type: String.to_atom(etype), head: head, post: post, title: "\"Post\""}
      end
    else
      %Embed{type: :post, head: head, post: post, title: "\"Post\""}
    end
  end

  def embed_feed_generator(head, feed, _media, auth) do
    %Embed{
      type: :feed_generator,
      head: head,
      creator: build_author(feed["creator"], auth),
      summary: build_author(feed, auth),
      title: "\"Feed\""
    }
  end

  def embed_list(head, list, _media, auth) do
    list = build_list(list, auth)

    %Embed{
      type: :list,
      head: head,
      list: list,
      creator: build_author(list["creator"], auth),
      summary: build_author(list, auth),
      title: "\"List\""
    }
  end

  def build_list(list, auth) do
    {ltype, _} = split_type(list["purpose"])

    ltype =
      ltype
      |> String.split(".")
      |> List.last()
      |> String.replace_trailing("list", "")
      |> String.to_atom()

    items =
      Map.get(list, "items", [])
      |> Enum.map(&build_list_item(&1, auth))

    %BsList{
      type: ltype,
      items: items
    }
  end

  def build_list_item(%{"uri" => uri} = item, auth) do
    subject = build_author(item["author"], auth)
    %BsListItem{uri: uri, subject: subject}
  end

  def build_list_item(_, _), do: nil

  def build_author(%{"did" => did} = author, auth) do
    author = Bluesky.try_resolve_author(author, auth)

    %Author{
      did: did,
      uri: author["uri"],
      cid: author["cid"],
      handle: author["handle"],
      avatar: author["avatar"],
      display_name: Map.get(author, "displayName", did),
      description: author["description"]
    }
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

  def to_date(nil), do: nil

  def to_date(date_str) do
    case Timex.parse(date_str, "{RFC3339z}") do
      {:ok, %DateTime{} = date} -> date
      _ -> nil
    end
  end

  def date(nil), do: ""

  def date(dt) do
    tz = Sandbox.Application.timezone()

    dt
    |> Timex.Timezone.convert(tz)
    |> Timex.format!("{Mshort} {D} at {h12}:{m}{am}")
  end

  def display_name(uri, auth) do
    did = Bluesky.get_authority(uri)

    case Bluesky.get_profile(did, auth) do
      {:ok, %{"displayName" => display_name}} -> display_name
      _ -> did
    end
  end
end
