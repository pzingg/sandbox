defmodule Sandbox.Bluesky.FeedFixtures do

  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.AppPassword

  def feed_item_fixture(i, auth \\ nil) do
    file_name =
      Path.join("test/support/fixtures/bluesky", "bsky-feed-item-#{i}.json")
      |> Path.expand()
    {:ok, contents} = File.read(file_name)
    {:ok, item} = Jason.decode(contents)
    if is_nil(auth) do
      app_password = AppPassword.load!()
      {:ok, auth} = Bluesky.login(app_password)
      {item, auth}
    else
      {item, auth}
    end
  end
end
