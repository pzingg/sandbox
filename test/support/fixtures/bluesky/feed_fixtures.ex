defmodule Sandbox.Bluesky.FeedFixtures do

  def feed_item_fixture(i) do
    file_name =
      Path.join("test/support/fixtures/bluesky", "bsky-feed-item-#{i}.json")
      |> Path.expand()
    {:ok, contents} = File.read(file_name)
    {:ok, item} = Jason.decode(contents)
    item
  end
end
