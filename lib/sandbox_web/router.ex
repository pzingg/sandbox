defmodule SandboxWeb.Router do
  use SandboxWeb, :router

  import SandboxWeb.Authentication, only: [require_authenticated_user: 2]

  alias SandboxWeb.MountHooks

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SandboxWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/oauth", SandboxWeb do
    pipe_through :browser

    get "/:provider", AuthController, :index
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :delete
  end

  scope "/oauth", SandboxWeb do
    pipe_through :api

    get "/:provider/client-metadata.json", AuthController, :client_metadata
  end

  scope "/", SandboxWeb do
    pipe_through :browser

    get "/logo.png", PageController, :logo
    get "/policy", PageController, :policy
    get "/tos", PageController, :tos

    live_session :authenticated, on_mount: {MountHooks, :user} do
      live "/account", AccountLive, :index
    end

    live_session :default, on_mount: MountHooks do
      live "/bluesky", BlueskyLive, :index
      live "/sandbox", SandboxLive, :index
      live "/", PageLive, :index
    end
  end
end
