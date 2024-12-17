defmodule SandboxWeb.Bluesky.FeedComponents do
  @moduledoc false

  use Phoenix.Component

  import SandboxWeb.CoreComponents, only: [icon: 1]

  alias Sandbox.Bluesky.Feed
  alias Sandbox.Bluesky.Feed.{Attachment, Author, Link, Post, Reply}

  attr :post, Post, required: true

  def skeet(assigns) do
    ~H"""
    <div class="grid gap-2 my-4 skeet top-level-post grid-cols-timeline-2">
      <!-- column 1 -->
      <div :if={Post.repost?(@post)}>
        &nbsp;
      </div>
      <!-- column 2 -->
      <div :if={Post.repost?(@post)}>
        <.reposted_by :if={Post.repost?(@post)} by={@post.reason.by} />
      </div>
      <!-- column 1 -->
      <div>
        <img class="w-12 h-12 rounded-full post-avatar" src={@post.author.avatar} />
      </div>
      <!-- column 2 -->
      <div>
        <div class="post-header">
          <span class="font-bold post-author"><%= @post.author.display_name %></span>&nbsp;<span class="post-handle"><%= @post.author.handle %></span>&nbsp;<span class="text-gray-500 post-date"><%= Feed.date(@post.date) %></span>
        </div>
        <div class="my-2 post-body">
          <.rich_text spans={Feed.link_spans(@post.text, @post.links)} />
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
          <img class="w-6 h-6 rounded-full quote-post-avatar" src={@post.author.avatar} />
        </div>
        <div class="flex-auto">
          <span :if={@post.author.display_name} class="font-bold quote-post-author"><%= @post.author.display_name %></span>
          <span class="post-handle"><%= @post.author.handle %></span>
        </div>
      </div>
      <div class="quote-post-body">
        <div class="p-2 quote-post-text">
          <.rich_text spans={Feed.link_spans(@post.text, @post.links)} />
        </div>
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
      <span :if={@by.display_name} class="font-bold repost-author"><%= @by.display_name %></span>
      <span class="repost-handle"><%= @by.handle %></span>
    </div>
    """
  end

  attr :reply_parent, Reply, required: true

  def in_reply_to(assigns) do
    ~H"""
    <%= case @reply_parent.type do %>
      <% :not_found -> %>
        <.in_reply_to_not_found uri={@reply_parent.uri} />
      <% :blocked -> %>
        <.in_reply_to_author author={@reply_parent.author} head="Reply blocked by" />
      <% _ -> %>
        <.in_reply_to_author author={@reply_parent.author} head="In reply to" />
    <% end %>
    """
  end

  attr :uri, :string, required: true

  def in_reply_to_not_found(assigns) do
    ~H"""
    <div class="my-2 post-in-reply-to" uri={@uri}>
      <.icon class="mr-2 small-icon" name="hero-arrow-uturn-left-solid" />
      <span class="post-reply-head">Deleted post</span>
    </div>
    """
  end

  attr :author, Author, required: true
  attr :head, :string, default: "In reply to"

  def in_reply_to_author(assigns) do
    ~H"""
    <div class="my-2 post-in-reply-to">
      <.icon class="mr-2 small-icon" name="hero-arrow-uturn-left-solid" />
      <span class="post-reply-head"><%= @head %></span>
      <span :if={@author.display_name} class="font-bold post-reply-author"><%= @author.display_name %></span>
      <span class="post-reply-handle"><%= @author.handle %></span>
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
            <%= text %>
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
      <a class="text-blue-700 underline" href={@uri}><%= @text %></a>
    </span>
    """
  end

  attr :text, :string, required: true
  attr :tag, :string, required: true

  def rich_text_tag(assigns) do
    ~H"""
    <span class="text-blue-700 link-tag" data-tag={@tag}><%= @text %></span>
    """
  end

  attr :text, :string, required: true
  attr :mention, Author, required: true

  def rich_text_mention(assigns) do
    ~H"""
    <span class="text-blue-700 link-mention" data-mention-did={@mention.did}><%= @text %></span>
    """
  end

  attr :images, :list, required: true

  def post_images(assigns) do
    # TODO: scale images down and arrange in grid if 2, 3, or 4 images
    ~H"""
    <div class="my-2 rounded-xl post-images">
      <%= case @images do %>
        <% [image] -> %>
          <.post_image image={image} />
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

  def post_image(assigns) do
    ~H"""
    <div class="my-2 post-images post-image">
      <img
        class="rounded-xl"
        src={@image.thumb}
        alt={@image.alt}
        height={@image.height}
        width={@image.width}
      />
    </div>
    """
  end

  attr :img_1, Attachment, required: true
  attr :img_2, Attachment, required: true

  def post_image_grid_2(assigns) do
    ~H"""
    <div class="grid grid-cols-2 grid-rows-1 gap-1 my-2 auto-rows-fr post-images post-image-grid-2">
      <div class="post-image">
        <img
          class="rounded-l-xl"
          src={@img_1.thumb}
          alt={@img_1.alt}
          height={@img_1.height}
          width={@img_1.width}
        />
      </div>
      <div class="post-image">
        <img
          class="rounded-r-xl"
          src={@img_2.thumb}
          alt={@img_2.alt}
          height={@img_2.height}
          width={@img_2.width}
        />
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
      <div class="row-span-2 post-image">
        <img
          class="rounded-l-xl"
          src={@img_1.thumb}
          alt={@img_1.alt}
          height={@img_1.height}
          width={@img_1.width}
        />
      </div>
      <div class="post-image">
        <img
          class="rounded-tr-xl"
          src={@img_2.thumb}
          alt={@img_2.alt}
          height={@img_2.height}
          width={@img_2.width}
        />
      </div>
      <div class="post-image">
        <img
          class="rounded-br-xl"
          src={@img_3.thumb}
          alt={@img_3.alt}
          height={@img_3.height}
          width={@img_3.width}
        />
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
      <div class="post-image">
        <img
          class="rounded-tl-xl"
          src={@img_1.thumb}
          alt={@img_1.alt}
          height={@img_1.height}
          width={@img_1.width}
        />
      </div>
      <div class="post-image">
        <img
          class="rounded-tr-xl"
          src={@img_3.thumb}
          alt={@img_3.alt}
          height={@img_3.height}
          width={@img_3.width}
        />
      </div>
      <div class="post-image">
        <img
          class="rounded-bl-xl"
          src={@img_2.thumb}
          alt={@img_2.alt}
          height={@img_2.height}
          width={@img_2.width}
        />
      </div>
      <div class="post-image">
        <img
          class="rounded-br-xl"
          src={@img_4.thumb}
          alt={@img_4.alt}
          height={@img_4.height}
          width={@img_4.width}
        />
      </div>
    </div>
    """
  end

  attr :video, Attachment, required: true

  def post_video(assigns) do
    # TODO: scale video down
    ~H"""
    <div class="rounded-xl post-video">
      <video width={@video.width} height={@video.height} src={@video.source} controls />
    </div>
    """
  end

  attr :external, Attachment, required: true

  def post_external(assigns) do
    ~H"""
    <div class="my-4 border-2 border-blue-400 rounded-xl post-external">
      <div :if={@external.thumb} class="my-2 rounded-2-xl external-images">
        <img src={@external.thumb} class="rounded-2-xl external-image" />
      </div>
      <div :if={@external.title} class="m-2 font-bold external-title">
        <a class="text-blue-700 underline" href={@external.uri}><%= @external.title %></a>
      </div>
      <div :if={@external.description} class="m-2 external-description">
        <%= @external.description %>
      </div>
      <div class="m-2 external-footer">
        <.icon class="mr-2 small-icon" name="hero-globe-alt" />
        <span><%= @external.domain %></span>
      </div>
    </div>
    """
  end
end
