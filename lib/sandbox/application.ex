defmodule Sandbox.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @default_client_scope "atproto transition:generic"
  @default_timezone "America/Los_Angeles"

  @default_ngrok_envs []
  # @default_ngrok_envs [:dev, :test]

  @impl true
  def start(_type, _args) do
    children = [
      SandboxWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:sandbox, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sandbox.PubSub},
      # Start a worker by calling: Sandbox.Worker.start_link(arg)
      # {Sandbox.Worker, arg},
      {Cachex, [:bluesky]},
      # Start to serve requests, typically the last entry
      SandboxWeb.Endpoint
    ]

    children =
      if using_ngrok?() do
        endpoint_config = Application.get_env(:sandbox, SandboxWeb.Endpoint)
        port = get_in(endpoint_config, [:http, :port])
        IO.puts("Ngrok will be bound to port #{port}")

        children ++ [{Ngrok, port: port, name: Sandbox.Ngrok}]
      else
        children
      end

    # Set "global" client scope on startup
    bluesky_config = Application.get_env(:sandbox, Sandbox.Bluesky, [])
    scope = Keyword.get(bluesky_config, :client_scope, @default_client_scope)
    set_bluesky_client_scope(scope)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sandbox.Supervisor]
    result = Supervisor.start_link(children, opts)

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SandboxWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def public_url do
    if using_ngrok?() do
      Ngrok.public_url(Sandbox.Ngrok)
    else
      SandboxWeb.Endpoint.url()
    end
  end

  def timezone do
    bluesky_config = Application.get_env(:sandbox, Sandbox.Bluesky, [])
    Keyword.get(bluesky_config, :timezone, @default_timezone)
  end

  def confidential_client? do
    bluesky_config = Application.get_env(:sandbox, Sandbox.Bluesky, [])
    Keyword.get(bluesky_config, :client_type) == :confidential
  end

  def app_password_file do
    bluesky_config = Application.get_env(:sandbox, Sandbox.Bluesky, [])
    Keyword.get(bluesky_config, :app_password_file)
  end

  def set_bluesky_client_scope(nil), do: :ok

  def set_bluesky_client_scope(scope) do
    :persistent_term.put("sandbox.bluesky.scope", scope)
  end

  def bluesky_client_scope do
    :persistent_term.get("sandbox.bluesky.scope", @default_client_scope)
  end

  defp using_ngrok? do
    ngrok_envs = Application.get_env(:sandbox, :ngrok_envs, @default_ngrok_envs)
    Mix.env() in ngrok_envs
  end
end
