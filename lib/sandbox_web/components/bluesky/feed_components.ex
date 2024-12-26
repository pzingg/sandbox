defmodule SandboxWeb.Bluesky.FeedComponents do
  @moduledoc false

  use Phoenix.Component

  import SandboxWeb.CoreComponents, only: [icon: 1]

  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.Feed

  alias Sandbox.Bluesky.Feed.{
    Attachment,
    Author,
    FeedGenerator,
    GraphList,
    Link,
    Post,
    PostInfo,
    StarterPack
  }

  attr :count, :integer, required: true
  attr :feed_name, :string, required: true

  def feed_header(assigns) do
    ~H"""
    <h2 class="my-4 text-2xl">
      {@count} recent posts from <span class="font-bold">{@feed_name}</span>
    </h2>
    """
  end

  attr :return_to, :string, required: true

  def thread_header(assigns) do
    ~H"""
    <h2 class="my-4 text-2xl">
      <span class="font-bold">Thread</span>
    </h2>
    <div class="my-2">
      <button class="button" type="button">
        <.link patch={@return_to}>Back</.link>
      </button>
    </div>
    """
  end

  attr :post, Post, required: true
  attr :live_action, :atom, default: nil
  attr :rest, :global, include: ~w(phx-click)

  def skeet(assigns) do
    ~H"""
    <div class="grid gap-2 skeet top-level-post grid-cols-timeline-2">
      <!-- column 1 -->
      <div :if={Post.repost?(@post)}>
        &nbsp;
      </div>
      <!-- column 2 -->
      <div :if={Post.repost?(@post)}>
        <.reposted_by :if={Post.repost?(@post)} by={@post.reason.by} />
      </div>
      <!-- column 1 -->
      <div
        class="flex flex-col post-avatar"
        {@rest}
        phx-value-reply={Post.reply?(@post)}
        phx-value-post_uri={Feed.encode_post_uri(@post, :uri)}
        phx-value-root_uri={Feed.encode_post_uri(@post, :reply_root_uri)}
      >
        <div class="flex-none">
          <img
            class="w-12 h-12 rounded-full"
            src={@post.author.avatar}
            alt={@post.author.display_name}
          />
        </div>
        <%= if @post.next_thread? do %>
          <div class="flex-1 my-2 post-next-thread">
            <svg
              class="w-full h-full next-thread-line"
              viewBox="0 0 100 100"
              preserveAspectRatio="none"
            >
              <line
                class="stroke-2 stroke-bluesky"
                x1="50%"
                y1="0"
                x2="50%"
                y2="100%"
                vector-effect="non-scaling-stroke"
              />
            </svg>
          </div>
        <% end %>
      </div>
      <!-- column 2 -->
      <div
        class="mb-4 post-item"
        {@rest}
        phx-value-reply={Post.reply?(@post)}
        phx-value-post_uri={Feed.encode_post_uri(@post.uri)}
        phx-value-root_uri={Feed.encode_post_uri(@post, :reply_root_uri)}
      >
        <div class="post-header">
          <span class="font-bold post-author">{@post.author.display_name}</span>
          <span class="post-handle">@{@post.author.handle}</span>
          <span class="text-gray-500 post-date">{Bluesky.local_date(@post.date)}</span>
        </div>
        <div class="flex gap-2 post-uri">
          <%= if @post.reply_level > 0 do %>
            <div class="flex-none">
              <.icon class="small-icon" name="hero-list-bullet" />
              {@post.reply_level}
            </div>
          <% end %>
          <%= if @post.reply_count > 0 do %>
            <div class="flex-none">
              <.icon class="small-icon" name="hero-chat-bubble-oval-left-ellipsis" />
              {@post.reply_count}
            </div>
          <% end %>
          <div class="flex-1 text-bluesky">{@post.uri}</div>
        </div>
        <div class="my-2 post-body">
          <div class="post-text">
            <.rich_text spans={Feed.link_spans(@post.text, @post.links)} />
          </div>
          <.post_feed_generator
            :if={Post.has_feed_generator?(@post)}
            feed={Post.feed_generator(@post)}
          />
          <.post_list :if={Post.has_list?(@post)} list={Post.list(@post)} />
          <.post_starter_pack
            :if={Post.has_starter_pack?(@post)}
            starter_pack={Post.starter_pack(@post)}
          />
          <.post_images :if={Post.has_images?(@post)} images={Post.images(@post)} />
          <.post_video :if={Post.has_video?(@post)} video={Post.video(@post)} />
          <.post_external :if={Post.has_external?(@post)} external={Post.external(@post)} />
          <.in_reply_to :if={Post.reply?(@post)} reply_parent={@post.reply_parent} />
          <.quote_post :if={Post.quote_post?(@post)} post={Post.quoted_post(@post)} />
        </div>
      </div>
    </div>
    """
  end

  attr :post, Post, required: true

  def quote_post(assigns) do
    ~H"""
    <div class="my-2 bg-gray-100 rounded-xl skeet quote-post">
      <div class="flex p-2 quote-post-header">
        <div class="flex-none w-8">
          <img
            class="w-6 h-6 rounded-full quote-post-avatar"
            src={@post.author.avatar}
            alt={@post.author.display_name}
          />
        </div>
        <div class="flex-auto">
          <span :if={@post.author.display_name} class="font-bold quote-post-author">
            {@post.author.display_name}
          </span>
          <span class="post-handle">@{@post.author.handle}</span>
        </div>
      </div>
      <div class="quote-post-body">
        <div class="p-2 quote-post-text">
          <.rich_text spans={Feed.link_spans(@post.text, @post.links)} />
        </div>
        <.post_feed_generator :if={Post.has_feed_generator?(@post)} feed={Post.feed_generator(@post)} />
        <.post_list :if={Post.has_list?(@post)} list={Post.list(@post)} />
        <.post_starter_pack
          :if={Post.has_starter_pack?(@post)}
          starter_pack={Post.starter_pack(@post)}
        />
        <.post_images :if={Post.has_images?(@post)} images={Post.images(@post)} />
        <.post_video :if={Post.has_video?(@post)} video={Post.video(@post)} />
        <.post_external :if={Post.has_external?(@post)} external={Post.external(@post)} />
      </div>
    </div>
    """
  end

  attr :by, Author, required: true

  def reposted_by(assigns) do
    ~H"""
    <div class="post-reposted-by">
      <.icon class="mr-2 small-icon" name="hero-arrow-path-rounded-square-solid" />
      <span class="repost-head">Reposted by</span>
      <span :if={@by.display_name} class="font-bold repost-author">{@by.display_name}</span>
      <span class="repost-handle">@{@by.handle}</span>
    </div>
    """
  end

  attr :reply_parent, PostInfo, required: true

  def in_reply_to(assigns) do
    ~H"""
    <%= case @reply_parent.type do %>
      <% :not_found -> %>
        <.in_reply_to_basic uri={@reply_parent.uri} head="Reply to a post" />
      <% :blocked -> %>
        <.in_reply_to_basic head="Reply to a blocked post" />
      <% :detached -> %>
        <.in_reply_to_basic head="Reply to a detached post" />
      <% _author -> %>
        <.in_reply_to_author author={@reply_parent.author} head="In reply to" />
    <% end %>
    """
  end

  attr :head, :string, required: true
  attr :uri, :string, default: nil

  def in_reply_to_basic(assigns) do
    ~H"""
    <div class="my-2 post-in-reply-to" uri={@uri}>
      <.icon class="mr-2 small-icon" name="hero-arrow-uturn-left-solid" />
      <span class="post-reply-head">{@head}</span>
    </div>
    """
  end

  attr :author, Author, required: true
  attr :head, :string, default: "Reply to"

  def in_reply_to_author(assigns) do
    ~H"""
    <div class="my-2 post-in-reply-to">
      <.icon class="mr-2 small-icon" name="hero-arrow-uturn-left-solid" />
      <span class="post-reply-head">{@head}</span>
      <span :if={@author.display_name} class="font-bold post-reply-author">
        {@author.display_name}
      </span>
      <span class="post-reply-handle">@{@author.handle}</span>
    </div>
    """
  end

  attr :spans, :list, required: true

  def rich_text(assigns) do
    ~H"""
    <div class="post-text">
      <%= for span <- @spans do %>
        <%= case span do %>
          <% {text, %Link{type: :uri, uri: uri}} -> %>
            <.rich_text_uri text={text} uri={uri} />
          <% {text, %Link{type: :tag, tag: tag}} -> %>
            <.rich_text_tag text={text} tag={tag} />
          <% {text, %Link{type: :mention, mention: mention}} -> %>
            <.rich_text_mention text={text} mention={mention} />
          <% {text, _link} -> %>
            {Bluesky.text_with_br(text)}
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :text, :string, required: true
  attr :uri, :string, required: true

  def rich_text_uri(assigns) do
    ~H"""
    <span class="link-uri">
      <a class="text-blue-700 underline" href={@uri}>{@text}</a>
    </span>
    """
  end

  attr :text, :string, required: true
  attr :tag, :string, required: true

  def rich_text_tag(assigns) do
    ~H"""
    <span class="text-blue-700 link-tag" data-tag={@tag}>{@text}</span>
    """
  end

  attr :text, :string, required: true
  attr :mention, Author, required: true

  def rich_text_mention(assigns) do
    ~H"""
    <span class="text-blue-700 link-mention" data-mention-did={@mention.did}>{@text}</span>
    """
  end

  attr :images, :list, required: true

  def post_images(assigns) do
    # TODO: scale images down and arrange in grid if 2, 3, or 4 images
    ~H"""
    <div class="my-2 rounded-xl post-images">
      <%= case @images do %>
        <% [image] -> %>
          <.post_image_single image={image} />
        <% [img_1, img_2] -> %>
          <.post_image_grid_2 img_1={img_1} img_2={img_2} />
        <% [img_1, img_2, img_3] -> %>
          <.post_image_grid_3 img_1={img_1} img_2={img_2} img_3={img_3} />
        <% [img_1, img_2, img_3, img_4] -> %>
          <.post_image_grid_4 img_1={img_1} img_2={img_2} img_3={img_3} img_4={img_4} />
      <% end %>
    </div>
    """
  end

  attr :image, Attachment, required: true

  def post_image_single(assigns) do
    ~H"""
    <div
      class="my-2 post-images post-image"
      phx-click="modal-image"
      phx-value-src={@image.thumb}
      phx-value-alt={@image.alt}
    >
      <img class="w-full rounded-xl" src={@image.thumb} alt={@image.alt} />
    </div>
    """
  end

  attr :img_1, Attachment, required: true
  attr :img_2, Attachment, required: true

  def post_image_grid_2(assigns) do
    ~H"""
    <div class="grid grid-cols-2 grid-rows-1 gap-1 my-2 auto-rows-fr post-images post-image-grid-2">
      <div
        class="post-image"
        phx-click="modal-image"
        phx-value-src={@img_1.thumb}
        phx-value-alt={@img_1.alt}
      >
        <img class="object-cover w-full h-half16x9 rounded-l-xl" src={@img_1.thumb} alt={@img_1.alt} />
      </div>
      <div
        class="post-image"
        phx-click="modal-image"
        phx-value-src={@img_2.thumb}
        phx-value-alt={@img_2.alt}
      >
        <img class="object-cover w-full h-half16x9 rounded-r-xl" src={@img_2.thumb} alt={@img_2.alt} />
      </div>
    </div>
    """
  end

  attr :img_1, Attachment, required: true
  attr :img_2, Attachment, required: true
  attr :img_3, Attachment, required: true

  def post_image_grid_3(assigns) do
    ~H"""
    <div class="grid grid-cols-2 grid-rows-2 gap-1 my-2 auto-rows-fr post-images post-image-grid-3">
      <div
        class="row-span-2 post-image"
        phx-click="modal-image"
        phx-value-src={@img_1.thumb}
        phx-value-alt={@img_1.alt}
      >
        <img class="object-cover w-full h-full16x9 rounded-l-xl" src={@img_1.thumb} alt={@img_1.alt} />
      </div>
      <div
        class="post-image"
        phx-click="modal-image"
        phx-value-src={@img_2.thumb}
        phx-value-alt={@img_2.alt}
      >
        <img class="object-cover w-full h-half16x9 rounded-tr-xl" src={@img_2.thumb} alt={@img_2.alt} />
      </div>
      <div
        class="post-image"
        phx-click="modal-image"
        phx-value-src={@img_3.thumb}
        phx-value-alt={@img_3.alt}
      >
        <img class="object-cover w-full h-half16x9 rounded-br-xl" src={@img_3.thumb} alt={@img_3.alt} />
      </div>
    </div>
    """
  end

  attr :img_1, Attachment, required: true
  attr :img_2, Attachment, required: true
  attr :img_3, Attachment, required: true
  attr :img_4, Attachment, required: true

  def post_image_grid_4(assigns) do
    ~H"""
    <div class="grid grid-cols-2 grid-rows-2 gap-1 my-2 auto-rows-fr post-images post-image-grid-4">
      <div
        class="post-image"
        phx-click="modal-image"
        phx-value-src={@img_1.thumb}
        phx-value-alt={@img_1.alt}
      >
        <img class="object-cover w-full h-half16x9 rounded-tl-xl" src={@img_1.thumb} alt={@img_1.alt} />
      </div>
      <div
        class="post-image"
        phx-click="modal-image"
        phx-value-src={@img_3.thumb}
        phx-value-alt={@img_3.alt}
      >
        <img class="object-cover w-full h-half16x9 rounded-tr-xl" src={@img_3.thumb} alt={@img_3.alt} />
      </div>
      <div
        class="post-image"
        phx-click="modal-image"
        phx-value-src={@img_2.thumb}
        phx-value-alt={@img_2.alt}
      >
        <img class="object-cover w-full h-half16x9 rounded-bl-xl" src={@img_2.thumb} alt={@img_2.alt} />
      </div>
      <div
        class="post-image"
        phx-click="modal-image"
        phx-value-src={@img_4.thumb}
        phx-value-alt={@img_4.alt}
      >
        <img class="object-cover w-full h-half16x9 rounded-br-xl" src={@img_4.thumb} alt={@img_4.alt} />
      </div>
    </div>
    """
  end

  attr :video, Attachment, required: true

  def post_video(assigns) do
    ~H"""
    <div
      id={Bluesky.uri_to_id(@video.source, "video-container-", @video.instance)}
      class="my-2 overflow-hidden post-video-container rounded-xl"
      phx-update="ignore"
    >
      <video
        id={"video-#{@video.cid}-#{@video.instance}"}
        class="video-js vjs-feed-video post-video"
        phx-hook="Video"
        poster={@video.thumb}
        controls
        preload="none"
      >
        <source src={@video.source} type="application/x-mpegURL" />
      </video>
    </div>
    """
  end

  attr :external, Attachment, required: true

  def post_external(assigns) do
    ~H"""
    <div class="my-4 overflow-hidden border-2 border-bluesky rounded-xl post-external">
      <div :if={@external.thumb} class="mb-2 external-images">
        <img class="w-full external-image" src={@external.thumb} alt={Attachment.alt(@external)} />
      </div>
      <div class="m-2 font-bold external-title">
        <%= if @external.title do %>
          <a class="text-blue-700 underline" href={@external.uri}>{@external.title}</a>
        <% else %>
          <a class="text-blue-700 underline" href={@external.uri}>{@external.uri}</a>
        <% end %>
      </div>
      <div :if={@external.description} class="m-2 external-description">
        {@external.description}
      </div>
      <div class="m-2 external-footer">
        <.icon class="mr-2 small-icon" name="hero-globe-alt" />
        <span>{@external.domain}</span>
      </div>
    </div>
    """
  end

  attr :feed, FeedGenerator, required: true

  def post_feed_generator(assigns) do
    ~H"""
    <div class="my-2 feed-generator-card">
      <div class="p-2 border rounded-xl">
        <div class="grid gap-2 my-2 grid-cols-timeline-2">
          <div class="feed-avatar">
            <img class="w-12 h-12" src={@feed.summary.avatar} alt={@feed.summary.display_name} />
          </div>
          <div>
            <div class="font-bold feed-title">
              {@feed.summary.display_name}
            </div>
            <div class="feed-by">
              Feed by <span>@{@feed.creator.handle}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :list, GraphList, required: true

  def post_list(assigns) do
    ~H"""
    <div class="px-4 py-2 my-2 border border-bluesky p post-list rounded-xl">
      <div class="grid gap-2 my-2 list-info grid-cols-timeline-2">
        <div>
          <img class="w-12 h-12" src={@list.summary.avatar} />
        </div>
        <div>
          <div class="text-xl font-bold text-blue-700 underline list-title">
            <a href={@list.summary.uri}>{@list.summary.name}</a>
          </div>
          <div class="list-by">
            {GraphList.display_type(@list)} by <span>{@list.creator.handle}</span>
          </div>
        </div>
      </div>
      <div class="list-description">{@list.summary.description}</div>
    </div>
    """
  end

  attr :starter_pack, StarterPack, required: true

  def post_starter_pack(assigns) do
    ~H"""
    <div class="max-w-md mx-auto my-2 post-starter-pack">
      <.list_card list={@starter_pack.list} name={@starter_pack.name} />
      <div class="grid gap-2 my-4 starter-pack-info grid-cols-timeline-2">
        <div>
          <img class="w-12 h-12" src="/images/starter_pack_icon.png" />
        </div>
        <div>
          <div class="text-xl font-bold text-blue-700 underline starter-pack-title">
            <a href={StarterPack.bsky_starter_pack_url(@starter_pack)}>{@starter_pack.name}</a>
          </div>
          <div class="starter-pack-by">
            Starter pack by <span>@{@starter_pack.creator.handle}</span>
          </div>
        </div>
      </div>
      <div class="starter-pack-description">{@starter_pack.description}</div>
    </div>
    """
  end

  attr :list, GraphList, required: true
  attr :name, :string, required: true

  def list_card(assigns) do
    ~H"""
    <div class="py-4 mx-auto text-center text-white oxrflow-hidden bg-bluesky rounded-xl starter-pack-card ">
      <div>
        <div class="my-4 font-bold">JOIN THE CONVERSATION</div>
        <div class="flex flex-row justify-center mx-auto list-avatars">
          <div :for={item <- GraphList.avatar_list(@list)} class="w-16 h-16">
            <img
              class="border-4 rounded-full border-bluesky list-avatar"
              src={item.subject.avatar}
              alt={item.subject.display_name}
            />
          </div>
        </div>
      </div>
      <div class="my-4 text-2xl font-bold list-card-name">{@name}</div>
    </div>
    """
  end
end
