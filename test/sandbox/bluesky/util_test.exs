defmodule Sandbox.Bluesky.UtilTest do
  use ExUnit.Case, async: true

  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.{AtURI, Feed}

  test "parses an at-uri" do
    uri = "at://did:plc:z7tqw2wfogaxv3pyrmtym7sh/app.bsky.feed.post/3ldhjrg7ack2g?stream=1#here"
    assert {:ok, uri} = AtURI.parse(uri)
    assert uri.host == "did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert uri.path == "/app.bsky.feed.post/3ldhjrg7ack2g"
    assert uri.query == "stream=1"
    assert uri.fragment == "here"
    assert AtURI.origin(uri) == "at://did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert AtURI.collection(uri) == "app.bsky.feed.post"
    assert AtURI.rkey(uri) == "3ldhjrg7ack2g"
  end

  test "parses a relative at-uri" do
    uri = "/app.bsky.graph.listitem/3lcxori7t5r2c?stream=2"
    base = "at://did:plc:z7tqw2wfogaxv3pyrmtym7sh/app.bsky.feed.post/3ldhjrg7ack2g#here"
    assert {:ok, uri} = AtURI.parse(uri, base)
    assert uri.host == "did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert uri.path == "/app.bsky.graph.listitem/3lcxori7t5r2c"
    assert uri.query == "stream=2"
    assert uri.fragment == "here"
    assert AtURI.origin(uri) == "at://did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert AtURI.collection(uri) == "app.bsky.graph.listitem"
    assert AtURI.rkey(uri) == "3lcxori7t5r2c"
  end

  test "builds a new at-uri" do
    assert {:ok, uri} =
             AtURI.new(
               "did:plc:z7tqw2wfogaxv3pyrmtym7sh",
               "app.bsky.graph.listitem",
               "3lcxori7t5r2c"
             )

    assert uri.host == "did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert uri.path == "/app.bsky.graph.listitem/3lcxori7t5r2c"
    assert AtURI.origin(uri) == "at://did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert AtURI.collection(uri) == "app.bsky.graph.listitem"
    assert AtURI.rkey(uri) == "3lcxori7t5r2c"
  end

  test "sets the collection in an at-uri" do
    uri = "at://did:plc:z7tqw2wfogaxv3pyrmtym7sh/app.bsky.feed.post/3ldhjrg7ack2g"
    assert {:ok, uri} = AtURI.parse(uri)
    uri = AtURI.set_collection(uri, "app.bsky.graph.listitem")
    assert uri.host == "did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert uri.path == "/app.bsky.graph.listitem/3ldhjrg7ack2g"
    assert AtURI.origin(uri) == "at://did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert AtURI.collection(uri) == "app.bsky.graph.listitem"
    assert AtURI.rkey(uri) == "3ldhjrg7ack2g"
  end

  test "sets the rkey in an at-uri" do
    uri = "at://did:plc:z7tqw2wfogaxv3pyrmtym7sh/app.bsky.feed.post/3ldhjrg7ack2g"
    assert {:ok, uri} = AtURI.parse(uri)
    uri = AtURI.set_rkey(uri, "3ldhirk3zcc2c")
    assert uri.host == "did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert uri.path == "/app.bsky.feed.post/3ldhirk3zcc2c"
    assert AtURI.origin(uri) == "at://did:plc:z7tqw2wfogaxv3pyrmtym7sh"
    assert AtURI.collection(uri) == "app.bsky.feed.post"
    assert AtURI.rkey(uri) == "3ldhirk3zcc2c"
  end

  test "intersperses br tags in text" do
    text = "Hello\n\nWorld\n\n"
    result = Bluesky.text_with_br(text)

    assert result == [
             "Hello",
             {:safe, "<br/>"},
             {:safe, "<br/>"},
             "World",
             {:safe, "<br/>"},
             {:safe, "<br/>"}
           ]

    assert safe_list_to_string(result) == "Hello<br/><br/>World<br/><br/>"
  end

  def safe_list_to_string(list) do
    Enum.map(list, fn
      bin when is_binary(bin) -> bin
      {:safe, _} = safe -> Phoenix.HTML.safe_to_string(safe)
    end)
    |> Enum.join("")
  end

  test "creates an id" do
    uri =
      "https://video.bsky.app/watch/did%3Aplc%3Aornpixmpy5ts36lh7hmi7wkp/bafkreibuhzkah544ypomtnj3ig3pmwpdgyh4b7g7wa5mqx3akkjfujduii/playlist.m3u8"

    id = Bluesky.uri_to_id(uri, "video-", 15)
    assert id == "video-bafkreibuhzkah544ypomtnj3ig3pmwpdgyh4b7g7wa5mqx3akkjfujduii-15"
  end

  test "creates a posts stream id" do
    post = %{
      instance: 15,
      uri: "at://did:plc:2orsuabrdskjpuglpru77po2/app.bsky.feed.post/3ld2hxl4lck2f"
    }

    id = Feed.Post.stream_id(post)
    assert id == "posts-did-plc-2orsuabrdskjpuglpru77po2-3ld2hxl4lck2f-15"
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
end
