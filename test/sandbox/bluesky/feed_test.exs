defmodule Sandbox.Bluesky.FeedTest do
  use ExUnit.Case, async: true

  import Sandbox.Bluesky.FeedFixtures

  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.{AppPassword, Feed}

  @moduletag :skip

  setup_all do
    app_password = AppPassword.load!()

    case Bluesky.login(app_password) do
      {:ok, auth} -> [auth: auth]
      {:error, message} -> [auth: message]
    end
  end

  test "parses feed item 0 (repost of quote post)", context do
    auth = flunk_if_no_auth(context)
    item = feed_item_fixture(0)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.repost?(post)
    refute Feed.Post.reply?(post)
    assert Feed.Post.quote_post?(post)
  end

  test "parses feed item 1 (reply)", context do
    auth = flunk_if_no_auth(context)
    item = feed_item_fixture(1)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    refute Feed.Post.repost?(post)
    assert Feed.Post.reply?(post)
    refute Feed.Post.quote_post?(post)
  end

  test "parses feed item 2 (quote post with image in quoted post)", context do
    auth = flunk_if_no_auth(context)
    item = feed_item_fixture(2)
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

  test "parses feed item 47 (quote post with media in quoted post)", context do
    auth = flunk_if_no_auth(context)
    item = feed_item_fixture(47)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    refute Feed.Post.repost?(post)
    refute Feed.Post.reply?(post)
    assert Feed.Post.quote_post?(post)

    quoted = Feed.Post.quoted_post(post)
    assert Feed.Post.has_images?(quoted)
    assert [image] = Feed.Post.images(quoted)

    assert image.thumb ==
             "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:djdxfzbvmvjmjlj3qu32uy2i/bafkreihn5b5k3nxf3ldoycng3o2alfy6r5tvhlo4mk72fvewubu7o2e2rq@jpeg"
  end

  test "parses feed item 8 (post with image)", context do
    auth = flunk_if_no_auth(context)
    item = feed_item_fixture(8)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.has_images?(post)
    assert [image] = Feed.Post.images(post)

    assert image.thumb ==
             "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:5o6k7jvowuyaquloafzn3cfw/bafkreiehnaalhj7pykvzfb2j67fq2j5jbwven53c2lbytppqu74n25tuqq@jpeg"
  end

  test "parses feed item 13 (post with video)", context do
    auth = flunk_if_no_auth(context)
    item = feed_item_fixture(13)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.has_video?(post)
    video = Feed.Post.video(post)

    assert video.source ==
             "https://video.bsky.app/watch/did%3Aplc%3A2ad7mmwmfprr6b3pkan46ub4/bafkreih225kpdjkewg5fbupmbex5upq5in6zevytvxjam5wukshlwwxkfu/playlist.m3u8"
  end

  test "parses feed item 15 (post with link)", context do
    auth = flunk_if_no_auth(context)
    item = feed_item_fixture(15)
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

  test "parses feed item 5 (post with external)", context do
    auth = flunk_if_no_auth(context)
    item = feed_item_fixture(5)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.has_external?(post)
    external = Feed.Post.external(post)
    assert external.domain == "jezebel.com"

    assert external.title ==
             "Jezebel's Person of the Year Is Anyone Who Donated to an Abortion Fund"
  end

  test "parses feed item 46 (feed generator view)", context do
    auth = flunk_if_no_auth(context)
    item = feed_item_fixture(46)
    post = Feed.decode_post(item, auth)
    # IO.inspect(post)
    assert Feed.Post.has_feed_generator?(post)
    feed_gen = Feed.Post.feed_generator(post)
    assert feed_gen.creator.display_name == "ændra."

    assert feed_gen.summary.description ==
             "Trending headlines from verified news organisations. Maintained by @aendra.com"
  end

  test "brute force", context do
    auth = flunk_if_no_auth(context)

    0..47
    |> Enum.each(fn i ->
      item = feed_item_fixture(i)
      _ = Feed.decode_post(item, auth)
    end)
  end

  test "get timeline", context do
    auth = flunk_if_no_auth(context)
    assert {:ok, data} = Bluesky.get_timeline(auth, limit: 50)
    assert is_list(data["feed"])
  end

  test "get discover feed", context do
    auth = flunk_if_no_auth(context)
    assert {:ok, data} = Bluesky.get_feed(auth, :discover, limit: 50)
    assert is_list(data["feed"])
  end

  test "gets a thread from the root", context do
    auth = flunk_if_no_auth(context)
    uri = "at://did:plc:di2xanilbluz4rmli3vf24mf/app.bsky.feed.post/3le3z7prt3c2o"
    {:ok, data} = Bluesky.get_post_thread(uri, auth, depth: 50)
    assert is_map(data["thread"])
    # File.write("thread-root-full.json", Jason.encode!(data, pretty: true))
  end

  test "gets a thread from the last post", context do
    auth = flunk_if_no_auth(context)
    uri = "at://did:plc:di2xanilbluz4rmli3vf24mf/app.bsky.feed.post/3le43qudhal2o"
    {:ok, data} = Bluesky.get_post_thread(uri, auth, depth: 50)
    assert is_map(data["thread"])
    # File.write("thread-last-full.json", Jason.encode!(data, pretty: true))
  end

  test "gets the last post in a thread", context do
    auth = flunk_if_no_auth(context)
    uri = "at://did:plc:di2xanilbluz4rmli3vf24mf/app.bsky.feed.post/3le43qudhal2o"
    {:ok, data} = Bluesky.get_posts([uri], auth)
    assert is_list(data["posts"])
    # File.write("post-last.json", Jason.encode!(data, pretty: true))
  end

  @tag skip: false
  test "splits a thread into branches", context do
    auth = flunk_if_no_auth(context)
    {:ok, contents} = File.read("test/support/fixtures/bluesky/thread-root-full.json")
    {:ok, data} = Jason.decode(contents)
    posts = Feed.decode_thread(data, auth, raw: true)
    assert Enum.count(posts) == 37
    zero_depth = Enum.filter(posts, fn post -> post.depth == 0 end)
    parents = Enum.filter(posts, fn post -> post.depth < 0 end)
    replies = Enum.filter(posts, fn post -> post.depth > 0 end)
    assert Enum.count(zero_depth) == 1
    assert Enum.count(parents) == 0
    assert Enum.count(replies) == 36
    assert Feed.max_depth(posts) == 9
    assert [root] = Feed.roots(posts)
    assert root.uri == hd(posts).uri
    root_handle = hd(posts).author.handle
    branches = Feed.build_branches(posts, root_handle)
    # File.write("built-branches.json", Jason.encode!(branches, pretty: true))
    branches = Feed.prune_branches(branches, root_handle)
    # File.write("pruned-branches.json", Jason.encode!(branches, pretty: true))
    posts = Feed.enumerate_branches(branches, posts)
    # File.write("branched-posts.json", Jason.encode!(posts, pretty: true))
    assert Enum.count(posts) == 37
  end

  test "get list", context do
    auth = flunk_if_no_auth(context)
    list_uri = "at://did:plc:r2mpjf3gz2ygfaodkzzzfddg/app.bsky.graph.list/3lcvbzusxvc26"
    assert {:ok, data} = Bluesky.get_list(auth, list_uri, limit: 50)
    assert data["list"]["purpose"] == "app.bsky.graph.defs#referencelist"
    assert data["list"]["name"] == "City of Boston Bluesky Accounts"
    assert Enum.count(data["items"]) == 15
  end

  test "resolve list", context do
    auth = flunk_if_no_auth(context)
    list_uri = "at://did:plc:r2mpjf3gz2ygfaodkzzzfddg/app.bsky.graph.list/3lcvbzusxvc26"
    list = Bluesky.Feed.resolve_list(list_uri, auth)
    # IO.inspect(list)
    assert %Feed.GraphList{} = list
  end

  def flunk_if_no_auth(context) do
    case context[:auth] do
      %{access_token: _} = auth ->
        auth

      error ->
        flunk("No auth: #{error}")
    end
  end
end
