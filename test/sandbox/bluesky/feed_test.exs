defmodule Sandbox.Bluesky.FeedTest do
  use ExUnit.Case, async: true

  import Sandbox.Bluesky.FeedFixtures

  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.{AppPassword, Feed}

  test "creates a posts stream id" do
    post = %{uri: "at://did:plc:2orsuabrdskjpuglpru77po2/app.bsky.feed.post/3ld2hxl4lck2f"}
    id = Feed.posts_stream_id(post)
    assert id == "posts-did:plc:2orsuabrdskjpuglpru77po2-app.bsky.feed.post-3ld2hxl4lck2f"
  end

  test "sorts links by byte_start" do
    [first, second] =
      [
        %Feed.Link{byte_start: 30, byte_end: 45, type: :tag, tag: "second"},
        %Feed.Link{byte_start: 4, byte_end: 25, type: :tag, tag: "first"}
      ]
      |> Feed.Link.sort()

    assert first.tag == "first"
    assert second.tag == "second"
  end

  test "parses feed item 0 (repost of quote post)" do
    {item, auth} = feed_item_fixture(0)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.repost?(post)
    refute Feed.Post.reply?(post)
    assert Feed.Post.quote_post?(post)
  end

  test "parses feed item 1 (reply)" do
    {item, auth} = feed_item_fixture(1)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    refute Feed.Post.repost?(post)
    assert Feed.Post.reply?(post)
    refute Feed.Post.quote_post?(post)
  end

  test "parses feed item 2 (quote post with image in quoted post)" do
    {item, auth} = feed_item_fixture(2)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    refute Feed.Post.repost?(post)
    refute Feed.Post.reply?(post)
    assert Feed.Post.quote_post?(post)

    quoted = Feed.Post.quoted_post(post)
    assert Feed.Post.has_images?(quoted)
    assert [image] = Feed.Post.images(quoted)

    assert image.thumb ==
             "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:sx23ba2gptu5o6pkoapa5rvy/bafkreidsapzgtw3elhlhkgbspb5i5uw2qu7jlltdfio7g26i2bxryyelse@jpeg"
  end

  test "parses feed item 8 (post with image)" do
    {item, auth} = feed_item_fixture(8)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.has_images?(post)
    assert [image] = Feed.Post.images(post)

    assert image.thumb ==
             "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:5o6k7jvowuyaquloafzn3cfw/bafkreiehnaalhj7pykvzfb2j67fq2j5jbwven53c2lbytppqu74n25tuqq@jpeg"
  end

  test "parses feed item 13 (post with video)" do
    {item, auth} = feed_item_fixture(13)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.has_video?(post)
    video = Feed.Post.video(post)

    assert video.source ==
             "https://video.bsky.app/watch/did%3Aplc%3A2ad7mmwmfprr6b3pkan46ub4/bafkreih225kpdjkewg5fbupmbex5upq5in6zevytvxjam5wukshlwwxkfu/playlist.m3u8"
  end

  test "parses feed item 15 (post with link)" do
    {item, auth} = feed_item_fixture(15)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)

    assert is_list(post.links)
    assert Enum.count(post.links) > 0
    assert [{plain, _}, {linked, _}] = Feed.link_spans(post.text, post.links)
    assert plain == "lol "
    assert linked == "bsky.app/profile/nyti..."
    assert plain <> linked == post.text

    quoted = Feed.Post.quoted_post(post)
    assert is_list(quoted.links)
    assert Enum.count(quoted.links) > 0
    assert [{plain, _}, {linked, _}] = Feed.link_spans(quoted.text, quoted.links)

    assert plain ==
             "After the killing of UnitedHealthcare’s CEO, social media posts signaled to some a strong sense of dissatisfaction with the U.S. health insurance system. A poll from last year suggests that opinions on the industry are nuanced. "

    assert linked == "nyti.ms/3VA4u2Y"
    assert plain <> linked == quoted.text
  end

  test "parses feed item 5 (post with external)" do
    {item, auth} = feed_item_fixture(5)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.has_external?(post)
    external = Feed.Post.external(post)
    assert external.domain == "jezebel.com"

    assert external.title ==
             "Jezebel's Person of the Year Is Anyone Who Donated to an Abortion Fund"
  end

  test "parses feed item 46 (feed generator view)" do
    {item, auth} = feed_item_fixture(46)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.has_feed_generator?(post)
    feed_gen = Feed.Post.feed_generator(post)
    assert feed_gen.creator.display_name == "ændra."

    assert feed_gen.summary.description ==
             "Trending headlines from verified news organisations. Maintained by @aendra.com"
  end

  @tag :skip
  test "brute force" do
    0..45
    |> Enum.reduce(nil, fn i, auth ->
      {item, auth} = feed_item_fixture(i, auth)
      Feed.decode_post(item, auth)
      auth
    end)
  end

  test "get timeline" do
    app_password = AppPassword.load!()
    assert {:ok, auth} = Bluesky.login(app_password)
    assert auth.access_token
    assert {:ok, data} = Bluesky.get_timeline(auth, limit: 50)
    assert is_list(data["feed"])

    # Enum.with_index(data["feed"])
    # |> Enum.each(fn {item, i} ->
    #  File.write("bsky-feed-item-#{i}.json", Jason.encode!(item, pretty: true))
    # end)
  end

  test "get discover feed" do
    app_password = AppPassword.load!()
    assert {:ok, auth} = Bluesky.login(app_password)
    assert auth.access_token
    assert {:ok, data} = Bluesky.get_feed(auth, :discover, limit: 50)
    assert is_list(data["feed"])
  end
end
