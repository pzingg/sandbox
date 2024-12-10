defmodule SandboxWeb.AuthController do
  use SandboxWeb, :controller

  import SandboxWeb.Authentication, only: [log_in_user: 2]

  require Logger

  alias Sandbox.Bluesky

  @doc """
  This action is reached via `/oauth/:provider` and should redirect to the OAuth2 provider
  based on the chosen strategy.

  TODO Need to get did, etc. and initiate new flow
  """
  def index(conn, %{"provider" => "bluesky"}) do
    redirect(conn, to: ~p"/bluesky")
  end

  def index(conn, %{"provider" => provider}) do
    conn
    |> put_flash(:error, "You cannot use OAuth provider '#{provider}'")
    |> redirect(to: ~p"/")
  end

  def client_metadata(conn, %{"provider" => "bluesky"}) do
    # https://drafts.aaronpk.com/draft-parecki-oauth-client-id-metadata-document/draft-parecki-oauth-client-id-metadata-document.html#section-4.1
    # TODO Verify content_type: "application/json"
    render(conn, :client_metadata, scope: Sandbox.Application.bluesky_client_scope())
  end

  def client_metadata(conn, %{"provider" => provider}) do
    conn
    |> put_status(400)
    |> json(%{
      "error" => "provider",
      "error_description" => "Provider #{provider} is not supported"
    })
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out!")
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  @doc """
  This action is reached via `/oauth/:provider/callback` is the the callback URL that
  the OAuth2 provider will redirect the user back to with a `code` that will
  be used to request an access token. The access token will then be used to
  access protected resources on behalf of the user.

  Query params sent by Bluesky:
  - `"state"`
  - `"code"`
  - `"iss"`
  """
  def callback(conn, %{"provider" => provider} = params) do
    case redirect_from_ngrok(conn, params) do
      {:halt, conn} ->
        conn

      {_, conn} ->
        # Exchange an auth code for an access token
        with {:ok, client} <- get_token(provider, params),
             {:ok, user} <- get_user(provider, params, client) do
          # Store the user in the session under `:current_user` and redirect to /.
          # In most cases, we'd probably just store the user's ID that can be used
          # to fetch from the database. In this case, since this example app has no
          # database, I'm just storing the user map.
          #
          # If you need to make additional resource requests, you may want to store
          # the access token as well.
          #
          # TODO Don't store the whole user (includes a private key!)
          conn
          |> log_in_user(user)
          |> redirect(to: ~p"/account")
        else
          {:error, reason} ->
            conn
            |> put_flash(:error, "Failed to save user: #{reason}")
            |> redirect(to: ~p"/")
        end
    end
  end

  def callback(conn, %{"provider" => provider, "error" => _error} = params) do
    conn
    |> put_flash(:error, "Authentication error (#{provider}): #{error_description(params)}")
    |> redirect(to: "/")
  end

  def callback(conn, %{"provider" => provider} = params) do
    conn
    |> put_flash(:error, "Unable to handle response (#{provider}): #{inspect(params)}")
    |> redirect(to: "/")
  end

  defp redirect_from_ngrok(conn, params) do
    # If we are redirected to an ngrok host, need to redirect again!
    if is_nil(params["from_ngrok"]) && Regex.match?(~r/\.ngrok.*\.app/, conn.host) do
      localhost = SandboxWeb.Endpoint.url()
      local_url = "#{localhost}#{conn.request_path}?#{conn.query_string}&from_ngrok=1"
      Logger.error("Ngrok! redirecting to #{local_url}")
      {:halt, redirect(conn, external: local_url)}
    else
      {:cont, conn}
    end
  end

  defp get_token("bluesky", params), do: Bluesky.get_token(params)
  defp get_token(provider, _), do: {:error, "Provider #{provider} is not available"}

  defp get_user("bluesky", params, client) do
    case Bluesky.save_user(client, issuer: Map.get(params, "iss")) do
      {:ok, user} ->
        case Bluesky.get_user_profile(user) do
          {:ok, user_with_profile} ->
            Bluesky.update_user(user_with_profile)
            {:ok, user_with_profile}

          _error ->
            {:ok, user}
        end

      error ->
        error
    end
  end

  defp error_description(params) do
    Map.get(params, "error_description") ||
      Map.get(params, "message") ||
      Map.get(params, "error")
  end
end
