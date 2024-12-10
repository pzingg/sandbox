defmodule Sandbox.Bluesky do
  @moduledoc """
  An OAuth2 strategy for Bluesky.

  Authorization flow:

    1. The client starts by asking for the user’s account identifier (handle or DID).
    2. For an account identifier, the client resolves the identity to a DID document.
    3. The client extracts the declared PDS URL from the DID document, and then
      fetches the Resource Server and Authorization Server locations.
      "https://shimeji.us-east.host.bsky.network" might be the Resource Server,
      but "https://bsky.social" will be the Authorization Server.
    4. Authorization Server metadata is fetched and verified against requirements for
      atproto OAuth.
    5. The client makes an HTTPS POST (PAR) request to the Authorization Server’s
      `pushed_authorization_request_endpoint` URL, with a DPoP request header and with the
      request parameters in the form-encoded request body. The response will include
      a "request_uri".
    6. The client makes an HTTPS GET request to the Authorization Server's
      `authorization_endpoint', adding query params
      client_id, request_uri, login_hint, grant_type, response_type, scope, state,
      code_challenge, and code_challenge_method. After authenticating,
      it is supposed to redirect back.

    See https://github.com/bluesky-social/cookbook/tree/main/python-oauth-web-app
    for a Python implementation we can follow.
  """

  use OAuth2.Strategy

  use Phoenix.VerifiedRoutes,
    endpoint: SandboxWeb.Endpoint,
    router: SandboxWeb.Router,
    statics: SandboxWeb.static_paths()

  require Logger

  alias OAuth2.{AccessToken, Client, DPoP}
  alias OAuth2.Strategy.AuthCode

  defmodule PushedAuthRequest do
    @moduledoc """
    Encapsulates the response from a successful PAR request.
    """

    @type t() :: %__MODULE__{
            state: binary(),
            client: OAuth2.Client.t(),
            pkce_verifier: binary(),
            request_params: Keyword.t(),
            request_headers: Keyword.t(),
            dpop_nonce: binary() | nil,
            authorize_params: Keyword.t() | nil
          }

    @enforce_keys [
      :state,
      :client,
      :pkce_verifier,
      :request_params,
      :request_headers
    ]

    defstruct [
      :state,
      :client,
      :pkce_verifier,
      :request_params,
      :request_headers,
      :dpop_nonce,
      :authorize_params
    ]
  end

  defmodule AuthRequest do
    @moduledoc """
    Persisted data for the authorization flow.

    `dpop_private_jwk` is the JSON-encoded map of the JWK.
    """

    use Ecto.Schema

    embedded_schema do
      field(:state, :string)
      field(:did, :string)
      field(:issuer, :string)
      field(:dpop_private_jwk, :string)
      field(:pkce_verifier, :string)
      field(:dpop_nonce, :string)
      field(:scope, :string)
      field(:request_uri, :string)
    end

    def decode_jwk!(%AuthRequest{dpop_private_jwk: jwk}) do
      case OAuth2.JWK.from_json(jwk) do
        {:ok, jwk} -> jwk
        {:error, reason} -> raise RuntimeError, "JWK decoding error: #{reason}"
      end
    end
  end

  defmodule AuthUser do
    @moduledoc """
    Persisted data for an authenticated user.

    `dpop_private_jwk` is the JSON-encoded map of the JWK.
    """

    use Ecto.Schema

    embedded_schema do
      field(:did, :string)
      field(:handle, :string)
      field(:display_name, :string)
      field(:avatar_url, :string)
      field(:pds_url, :string)
      field(:auth_url, :string)
      field(:access_token, :string)
      field(:refresh_token, :string)
      field(:scope, :string)
      field(:expires_at, :integer)
      field(:dpop_private_jwk, :string)
      field(:dpop_nonce, :string)
    end

    def decode_jwk!(%AuthUser{dpop_private_jwk: jwk}) do
      case OAuth2.JWK.from_json(jwk) do
        {:ok, jwk} -> jwk
        {:error, reason} -> raise RuntimeError, "JWK decoding error: #{reason}"
      end
    end
  end

  # Strategy Callbacks

  @impl true
  @doc """
  Incoming `params` should include `:client_id` and `:request_uri`.
  """
  def authorize_url(client, params) do
    # We don't want the typical params that AuthCode will insert
    params = Enum.filter(params, fn {k, _v} -> k in [:client_id, :request_uri] end)

    %Client{client | params: %{}}
    |> merge_params(params)
  end

  @impl true
  @doc """
  Callback for an access token request using the client's `:token_method`.

  For the Bluesky DPoP request `:params` coming here from the strategy module
  (`Sandbox.Bluesky`) should include `:code` and `:code_verifier`.
  `AuthCode.get_token/2` will add `:client_id`, `:grant_type` and `:redirect_uri`.
  """
  def get_token(client, params, headers) do
    # AuthCode will add :grant_type, :client_id, and :redirect_uri
    # merge the supplied :code and :code_verifier into client.params
    %Client{client | params: %{}}
    |> AuthCode.get_token(params, headers)
  end

  # Public API

  @doc """
  Builds an OAuth2 Client for a Bluesky did.

  Options:
  - `:user` (optional) - if an `AuthUser, the JWK for the user will be loaded.
  - `:jwk` (optional) - JWK to be loaded into the client.

  Note: if `:user` is `nil` and `:jwk` not set, a new JWK will be created
  for the client.
  """
  @spec build_client!(String.t(), String.t(), Keyword.t()) :: Client.t()
  def build_client!(did, scope, opts \\ []) do
    jwk = Keyword.get(opts, :jwk)
    user = Keyword.get(opts, :user)

    jwk =
      case {jwk, user} do
        {%JOSE.JWK{} = j, _} ->
          if OAuth2.JWK.private_key_with_signer?(j) do
            j
          else
            raise ArgumentError, "Private key required"
          end

        {_, %AuthUser{} = u} ->
          AuthUser.decode_jwk!(u)

        _ ->
          get_private_jwk()
      end

    client =
      client_config(did, scope)
      |> Client.new()
      |> Client.put_serializer("application/json", Jason)
      |> Client.put_param(:scope, scope)
      |> put_dpop_private_jwk(jwk)

    case user do
      %AuthUser{
        access_token: access_token,
        expires_at: expires_at,
        scope: scope,
        refresh_token: refresh_token
      } ->
        token =
          AccessToken.new(%{
            "access_token" => access_token,
            "token_type" => "DPoP",
            "expires_in" => expires_at,
            "subject" => did,
            "scope" => scope,
            "refresh_token" => refresh_token
          })

        %Client{client | token: token}

      _ ->
        client
    end
  end

  def authorize_url!(client, params) do
    Client.authorize_url!(client, params)
  end

  @doc """
  Makes an initial access token request using DPoP, after the OAuth
  authorization redirect.

  ## Arguments

  - `callback_params` - query string params (a map) as received at the
    `redirect_uri`. For Bluesky they will include `"state"`, `"code"`, and `"iss"`.
  """
  def get_token(callback_params) do
    %{"state" => state, "code" => code, "iss" => issuer} = callback_params

    case request_data_for_state(state, issuer) do
      {:ok, request_data} ->
        # Build a client using the JWK we used for authorization.
        jwk = AuthRequest.decode_jwk!(request_data)
        client = build_client!(request_data.did, request_data.scope, jwk: jwk)
        url = client.token_url
        nonce = request_data.dpop_nonce

        # We add the :code and :code_verifier to be merged into client.params.
        #
        # For confidential clients, would have to add
        # client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        # client_assertion: client_assertion (a JWT made from the DID's persistent private key)
        params = [
          code: code,
          code_verifier: request_data.pkce_verifier
        ]

        get_token_with_dpop(client, :get_token, params, url, jwk, nonce)

      error ->
        error
    end
  end

  def refresh_token(did) do
    case get_user(did) do
      {:ok, user} ->
        # Build a client with the `dpop_private_jwk` from `user`
        client = build_client!(did, user.scope, user: user)

        client =
          %Client{client | params: %{}}
          |> Client.put_param(:client_id, client.client_id)

        url = client.token_url
        jwk = client.dpop_private_jwk
        nonce = user.dpop_nonce

        # For confidential clients, would have to add to params
        # client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        # client_assertion: client_assertion (a JWT made from the DID's persistent private key)

        get_token_with_dpop(client, :refresh_token, [], url, jwk, nonce)

      error ->
        error
    end
  end

  @doc """
  Makes an access or refresh token request to the Bluesky OAuth token endpoint.
  After building a DPoP header, the request is build and made by calling
  `Client.get_token` to exchange an authorization code for the access token,
  or `Client.refresh_token`, to get a new access token.

  The required form encoded params for `get_token` are `"code"`, `"grant_type"`
  (`"authorization_code"`), `"client_id"`, `"redirect_uri"`, and `"code_verifier"`.

  The required params for `refresh_token` are `"refresh_token"`, `"grant_type"`
  (`"refresh_token"`), and `"client_id"`.

  For both `get_token` and `refresh_token` the first request will return a status 400
  JSON body with a `"use_dpop_nonce"` error, providing the nonce value in the response's
  `DPoP-Nonce` header.

  The second `get_token` or `refresh_token` request should succeed and return
  a JSON body with `"access_token"`, `"token_type"`, `"expires_in"`, `"scope"`,
  `"sub"`,  and `"refresh_token"` values.

  ## Arguments

  - `func` - either `:get_token` or `:refresh_token`
  - `params` - a keyword list of params to be added to the basic strategy params
    (see Notes below)
  - `url` - the OAuth2 token endpoint
  - `jwk` - the private JWK previously bound to the pushed authorization request
  - `nonce` - the nonce sent by the client or obtained from the authorization
    server's `"DPoP-Nonce"` response header.
  - `final` - initially `false`, then set to `true` when retrying after a 400
    `"use_dpop_nonce"` error

  ## Notes

  For `:get_token`, `:params` should include `:code` and `:code_verifier`; the
  `OAuth2.Client` adds the `"grant_type"`, `"client_id"`, and `"redirect_uri"`.

  For `:refresh_token` the client will already have the required `"client_id"`
  param set; the `OAuth2.Refresh` strategy adds `"refresh_token"` and `"grant_type"`.
  """
  def get_token_with_dpop(
        %Client{token_method: method} = client,
        func,
        params,
        url,
        jwk,
        nonce,
        final \\ false
      ) do
    case DPoP.proof(jwk, url, method: method, nonce: nonce) do
      {:ok, {dpop_token, _fields, _claims}} ->
        res = apply(Client, func, [client, params, [{"DPoP", dpop_token}]])

        Logger.info(
          "applying Client.#{func}, final: #{if final, do: "true", else: "false"}, res #{inspect(res)}"
        )

        case res do
          {:ok, client} ->
            # Stuff the nonce into the Client
            {:ok, %Client{client | dpop_nonce: nonce}}

          {:error, %OAuth2.Response{body: body} = response} ->
            # The server may request a different dpop_nonce!
            error_code = Map.get(body, "error")

            if !final && error_code == "use_dpop_nonce" do
              dpop_nonce = get_dpop_nonce(response.headers)

              if dpop_nonce do
                get_token_with_dpop(client, func, params, url, jwk, dpop_nonce, true)
              else
                {:error, "#Invalid #{func} response: no DPoP-Nonce header"}
              end
            else
              error = error_description(response)
              {:error, "#{func} error: #{error}"}
            end
        end
    end
  end

  defp error_description(%OAuth2.Response{body: %{"error_description" => msg}}), do: msg
  defp error_description(%OAuth2.Response{body: %{"message" => msg}}), do: msg
  defp error_description(%OAuth2.Response{body: %{"error" => msg}}), do: msg
  defp error_description(%OAuth2.Response{status_code: code}), do: "status #{code}"

  def raise_response_error(%OAuth2.Response{status_code: code, headers: headers, body: body}) do
    raise %OAuth2.Error{
      reason: """
      Server responded with status: #{code}

      Headers:

      #{Enum.reduce(headers, "", fn {k, v}, acc -> acc <> "#{k}: #{v}\n" end)}
      Body:

      #{inspect(body)}
      """
    }
  end

  @doc """
  Authorization flow with PAR.

  Returns a tuple {:ok, PushedAuthRequest.t()} or {:error, binary()}.
  """
  def authorization_flow(did, scope)

  def authorization_flow(did, scope) when is_binary(did) do
    with {:did, document} when is_map(document) <- {:did, resolve_did(did)},
         {:login_hint, {handle, _, _}} <- {:login_hint, get_handle(document)} do
      pushed_authorization_request(did, scope, login_hint: handle)
    else
      {:did, _} ->
        {:error, "Failed to resolve #{did}"}

      {:login_hint, _} ->
        {:error, "Failed to get handle from #{did}"}
    end
  end

  def authorization_flow(_, _), do: {:error, "No did"}

  @doc """
  A client sends the parameters that comprise an authorization request
  directly to the PAR endpoint. A typical parameter set might include:
  `"client_id"`, `"response_type"`, `"redirect_uri"`, `"scope"`, `"state"`,
  `"code"`, and `"code_challenge_method"`. A nonce is not initially
  supplied, and it is expected that the server will return a 400 status,
  with a nonce contained in the `"DPoP-Nonce"` response header.
  The client should retry with this server-supplied nonce

  However, the pushed authorization request can be composed of any of
  the parameters applicable for use at the authorization endpoint,
  including those defined in [RFC6749] as well as all applicable extensions.

  The `"request_uri"` authorization request parameter is one exception,
  and it MUST NOT be provided.

  ## Arguments

  - `did` - the DID for the client
  - `scope` - space-delimited scope, must include "atproto" (the default)
  - `params` - extra PAR body params, such as `:login_hint`. The special param
    `:test_only` will build and return the `PushedAuthRequest` data without
    actually executing the request.
  """
  def pushed_authorization_request(did, scope, params \\ []) do
    # Note from python-oauth-web-app:
    # Generate DPoP private signing key for this account session. In theory
    # this could be defered until the token request at the end of the
    # athentication flow, but doing it now allows early binding during
    # the PAR request.

    # Build a client with a new JWK for the authorization flow.
    client = build_client!(did, scope)

    state = generate_nonce()

    # Verifier is a cryptographic random string using the
    # unreserved characters [A-Z] / [a-z] / [0-9] / "-" / "." / "_" / "~"
    # with a minimum length of 43 characters and a maximum length of 128 characters.
    verifier = generate_nonce(64)
    challenge = base64_encoded_hash(verifier, "S256")

    # response_mode: "query", "fragment", or "form_post"
    # For "form_post", router should have `post "/:provider/callback", AuthController, :callback`
    # and URL must be publicly available (ngrok for dev server).
    # For "query", router should have `get "/:provider/callback", AuthController, :callback`
    # and "http://localhost:4000" is ok.
    #
    # For confidential clients, would have to add
    # client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    # client_assertion: client_assertion (a JWT made from the DID's persistent private key)
    {test_only, params} = Keyword.pop(params, :test_only)

    params =
      Keyword.merge(
        [
          client_id: client.client_id,
          scope: scope,
          response_mode: "query",
          response_type: "code",
          grant_type: "authorization_code",
          state: state,
          code_challenge: challenge,
          code_challenge_method: "S256"
        ],
        params
      )

    headers = [
      {"content-type", "application/x-www-form-urlencoded"},
      {"accept", "application/json"}
    ]

    request_data = %PushedAuthRequest{
      state: state,
      client: client,
      pkce_verifier: verifier,
      request_params: params,
      request_headers: headers
    }

    try_pushed_request(request_data, test_only)
  end

  def try_pushed_request(request_data, test_only, final \\ false) do
    case build_dpop_header(request_data) do
      {:ok, request_data} ->
        if test_only do
          {:ok, request_data}
        else
          case send_pushed_request(request_data, final) do
            # On :retry, request_data has dpop_nonce set
            {:retry, request_data} ->
              try_pushed_request(request_data, false, true)

            ok_or_error ->
              ok_or_error
          end
        end

      error ->
        error
    end
  end

  def build_dpop_header(request_data) do
    jwk = request_data.client.dpop_private_jwk
    url = request_data.client.par_url
    nonce = request_data.dpop_nonce

    case DPoP.proof(jwk, url, method: :post, nonce: nonce) do
      {:ok, {dpop_token, _fields, _claims}} ->
        headers = List.keydelete(request_data.request_headers, "DPoP", 0)

        {:ok,
         %PushedAuthRequest{request_data | request_headers: [{"DPoP", dpop_token} | headers]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns {:ok, PushedAuthRequest.t()} | {:retry, PushedAuthRequest.t()} | {:error, binary()}
  """
  def send_pushed_request(request_data, final) do
    %PushedAuthRequest{
      client: client,
      request_params: params,
      request_headers: headers
    } = request_data

    url = client.par_url

    case OAuth2.Request.request(:post, client, url, params, headers, decode_body: false) do
      {:ok, response} ->
        case response.body do
          %{"request_uri" => request_uri} ->
            authorize_params = [client_id: params[:client_id], request_uri: request_uri]
            request_data = %PushedAuthRequest{request_data | authorize_params: authorize_params}
            store_request_data(request_data)
            {:ok, request_data}

          _ ->
            {:error, "Invalid PAR response: no request_uri"}
        end

      {:error, response} ->
        error_code = Map.get(response.body, "error")

        if !final && error_code == "use_dpop_nonce" do
          # Fetch nonce from "DPoP-Nonce" header and try again.
          dpop_nonce = get_dpop_nonce(response.headers)

          if dpop_nonce do
            {:retry, %PushedAuthRequest{request_data | dpop_nonce: dpop_nonce}}
          else
            {:error, "Invalid PAR response: no DPoP-Nonce header"}
          end
        else
          error = error_description(response)
          {:error, "PAR response error: #{error}"}
        end
    end
  end

  def get_user_profile(%AuthUser{did: did, pds_url: pds_url} = user) do
    case xrpc_request(
           :get,
           pds_url,
           "app.bsky.actor.getProfile",
           [actor: did],
           user
         ) do
      {:ok, %OAuth2.Response{body: body} = _response} ->
        # File.write("user-profile.json", Jason.encode!(body))
        user = %AuthUser{user | avatar_url: body["avatar"], display_name: body["displayName"]}
        {:ok, user}

      error ->
        error
    end
  end

  @doc """
  For "procedure" Lexicon schema types, method is :post, otherwise :get.

  error_description: Invalid DPoP key binding.
  """
  def xrpc_request(method, server, nsid, params, auth \\ nil)

  def xrpc_request(:post, server, nsid, params, auth) do
    url = "#{server}/xrpc/#{URI.encode(nsid)}"
    headers = [{"Accept", "application/json"}]

    headers =
      if Enum.empty?(params) do
        headers
      else
        [{"Content-type", "application/json"} | headers]
      end

    with {:authed, %AuthUser{dpop_nonce: nonce}} <- {:authed, auth},
         jwk = AuthUser.decode_jwk!(auth),
         {:ok, {response, nonce}} <-
           xrpc_with_dpop(:post, url, params, headers, jwk, auth, nonce) do
      update_user(%{auth | dpop_nonce: nonce})
      {:ok, response}
    else
      {:authed, _non_authed} ->
        xrpc_non_authenticated(:post, url, params, headers)
    end
  end

  def xrpc_request(:get, server, nsid, params, auth) do
    url = "#{server}/xrpc/#{URI.encode(nsid)}"
    headers = [{"Accept", "application/json"}]

    with {:authed, %AuthUser{dpop_nonce: nonce}} <- {:authed, auth},
         jwk = AuthUser.decode_jwk!(auth),
         {:ok, {response, nonce}} <-
           xrpc_with_dpop(:get, url, params, headers, jwk, auth, nonce) do
      update_user(%{auth | dpop_nonce: nonce})
      {:ok, response}
    else
      {:authed, _non_authed} ->
        xrpc_non_authenticated(:get, url, params, headers)

      {:error, _reason} = error ->
        error
    end
  end

  def xrpc_with_dpop(method, url, params, req_headers, jwk, auth, nonce, final \\ false) do
    case xrpc_dpop_headers(method, url, jwk, auth, nonce) do
      {:ok, dpop_headers} ->
        opts =
          case method do
            :post -> [url: url, method: :post, headers: req_headers ++ dpop_headers, body: params]
            :get -> [url: url, method: :get, headers: req_headers ++ dpop_headers, params: params]
          end

        case Req.request(opts, decode_body: false) do
          {:ok, %Req.Response{status: status, headers: resp_headers, body: body}}
          when is_binary(body) ->
            case OAuth2.Request.process_body(&jason_serializer/1, status, resp_headers, body) do
              {:ok, response} ->
                {:ok, {response, nonce}}

              {:error, %OAuth2.Response{body: body} = response} ->
                # The server may request a different dpop_nonce!
                error_code = Map.get(body, "error")

                if !final && error_code == "use_dpop_nonce" do
                  dpop_nonce = get_dpop_nonce(response.headers)

                  if dpop_nonce do
                    xrpc_with_dpop(
                      method,
                      url,
                      params,
                      req_headers,
                      jwk,
                      auth,
                      dpop_nonce,
                      true
                    )
                  else
                    {:error, "Invalid token response: no DPoP-Nonce header"}
                  end
                else
                  error = error_description(response)
                  {:error, "Xrpc error: #{error}"}
                end
            end

          {:ok, %Req.Response{body: body}} ->
            {:error, "Response did not return a body #{inspect(body)}"}

          {:error, exc} ->
            {:error, %OAuth2.Error{reason: Exception.message(exc)}}
        end

      error ->
        error
    end
  end

  defp xrpc_dpop_headers(method, url, jwk, auth, nonce) do
    with {:authed, %{access_token: access_token, auth_url: issuer}} <- {:authed, auth},
         {:jwk, true} <- {:jwk, is_map(jwk)},
         ath_claims = %{
           "iss" => issuer,
           "ath" => base64_encoded_hash(access_token, "S256")
         },
         {:ok, {dpop_token, _fields, _claims}} <-
           DPoP.proof(jwk, url, method: method, nonce: nonce, claims: ath_claims) do
      {:ok,
       [
         {"Authorization", "DPoP #{access_token}"},
         {"DPop", dpop_token}
       ]}
    else
      {:authed, _} -> {:error, "Missing auth data"}
      {:jwk, _} -> {:error, "Invalid JWK"}
      error -> error
    end
  end

  def xrpc_non_authenticated(method, url, params, req_headers) do
    opts =
      case method do
        :post -> [url: url, method: :post, headers: req_headers, body: params]
        :get -> [url: url, method: :get, headers: req_headers, params: params]
      end

    case Req.request(opts, decode_body: false) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: body}}
      when is_binary(body) ->
        OAuth2.Request.process_body(&jason_serializer/1, status, resp_headers, body)

      {:ok, %Req.Response{body: body}} ->
        {:error, "Response did not return a body #{inspect(body)}"}

      {:error, exc} ->
        {:error, %OAuth2.Error{reason: Exception.message(exc)}}
    end
  end

  defp jason_serializer(_content_type), do: Jason

  @spec store_request_data(PushedAuthRequest.t()) :: {:ok, AuthRequest.t()} | {:error, String.t()}
  def store_request_data(%PushedAuthRequest{state: state} = request_data) do
    data = %AuthRequest{
      state: state,
      did: request_data.client.subject,
      issuer: request_data.client.site,
      dpop_private_jwk: OAuth2.JWK.to_json(request_data.client.dpop_private_jwk),
      pkce_verifier: request_data.pkce_verifier,
      dpop_nonce: request_data.dpop_nonce,
      scope: request_data.request_params[:scope],
      request_uri: request_data.authorize_params[:request_uri]
    }

    case Cachex.put(:bluesky, "par|#{state}", data) do
      {:ok, _} -> {:ok, data}
      _error -> {:error, "Failed to save auth request data"}
    end
  end

  @spec request_data_for_state(String.t(), String.t()) ::
          {:ok, AuthRequest.t()} | {:error, String.t()}
  def request_data_for_state(state, issuer) do
    case Cachex.get(:bluesky, "par|#{state}") do
      {:ok, %AuthRequest{issuer: request_issuer} = request_data} when is_binary(issuer) ->
        if issuer == request_issuer do
          {:ok, request_data}
        else
          {:error, "Invalid issuer #{issuer} for state #{state}"}
        end

      _ ->
        {:error, "Request not found for #{state}"}
    end
  end

  def delete_request_data(state) do
    Cachex.del(:bluesky, "par|#{state}")
  end

  @spec get_user(String.t()) :: {:ok, AuthUser.t()} | {:error, String.t()}
  def get_user(did) do
    case Cachex.get(:bluesky, "user|#{did}") do
      {:ok, user} when is_map(user) -> {:ok, user}
      _ -> {:error, "No user in database with DID #{did}"}
    end
  end

  @doc """
  Persist an authenticated client.

  `opts[:issuer]` (optional) - should be set to the "iss" value returned
  in the authoriztion callback.
  """
  @spec save_user(Client.t(), Keyword.t()) :: {:ok, AuthUser.t()} | {:error, String.t()}
  def save_user(client, opts \\ [])

  def save_user(%Client{token: %AccessToken{} = token} = client, opts) do
    with {:token, access_token} when is_binary(access_token) <- {:token, token.access_token},
         {:client, did} when is_binary(did) <- {:client, client.subject},
         {:client, %JOSE.JWK{} = jwk} <- {:client, client.dpop_private_jwk},
         {:client, nonce} when is_binary(nonce) <- {:client, client.dpop_nonce},
         {:resolution, did_document} when is_map(did_document) <- {:resolution, resolve_did(did)},
         {:resolution, {handle, _, _}} <- {:resolution, get_handle(did_document)},
         {:resolution, %{pds: pds_url, auth: auth_url}} <-
           {:resolution, get_service_urls(did_document)} do
      user = %AuthUser{
        did: did,
        handle: handle,
        pds_url: pds_url,
        auth_url: Keyword.get(opts, :issuer) || auth_url,
        access_token: access_token,
        expires_at: token.expires_at,
        scope: token.scope,
        refresh_token: token.refresh_token,
        dpop_private_jwk: OAuth2.JWK.to_json(jwk),
        dpop_nonce: nonce
      }

      case Cachex.put(:bluesky, "user|#{did}", user) do
        {:ok, _} -> {:ok, user}
        _error -> {:error, "Failed to save user"}
      end
    else
      {:token, _} ->
        {:error, "Client missing access token"}

      {:client, _} ->
        {:error, "Client missing subject, jwk, or nonce"}

      {:resolution, _} ->
        {:error, "Client DID resolution failed"}
    end
  end

  def store_user(_, _), do: {:error, "Must supply a tokenized client"}

  def update_user_tokens(did, %Client{token: %AccessToken{} = token}) do
    case Cachex.get_and_update(:bluesky, "user|#{did}", fn
           %AuthUser{} = user ->
             {:commit,
              Map.merge(user, %{
                access_token: token.access_token,
                refresh_token: token.refresh_token
              })}

           _ ->
             {:ignore, nil}
         end) do
      {:commit, user} -> {:ok, user}
      _ -> {:error, "No user in database with DID #{did}"}
    end
  end

  def update_user_tokens(_, _), do: {:error, "Must supply a tokenized client"}

  @spec update_user(AuthUser.t()) :: {atom(), any()}
  def update_user(%AuthUser{did: did} = user) do
    Cachex.put(:bluesky, "user|#{did}", user)
  end

  @doc """
  If a DID is provided, fetch the user's private key,
  otherwise generate a new private key.
  """
  def get_private_jwk(did \\ nil)

  def get_private_jwk(did) when is_binary(did) do
    case Cachex.get(:bluesky, "jwk|#{did}") do
      {:ok, jwk} when is_map(jwk) ->
        jwk

      _ ->
        jwk = OAuth2.JWK.generate_key!("ES256")
        Cachex.put(:bluesky, "jwk|#{did}", jwk)
        jwk
    end
  end

  def get_private_jwk(_) do
    OAuth2.JWK.generate_key!("ES256")
  end

  def get_dpop_nonce(headers) do
    case List.keyfind(headers, "dpop-nonce", 0) do
      {_, value} when is_binary(value) -> value
      {_, [value | _]} when is_binary(value) -> value
      _ -> nil
    end
  end

  @symbols ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._~"
  @symbol_count Enum.count(@symbols)

  @doc """
  Used for nonces and PKCE verifier strings.
  Constrained to [A-Z] / [a-z] / [0-9] / "-" / "." / "_" / "~"
  """
  def generate_nonce(len \\ 10) do
    for _ <- 1..len, into: "", do: <<Enum.at(@symbols, :rand.uniform(@symbol_count) - 1)>>
  end

  @supported_hash_methods %{
    "S256" => :sha256
  }

  def base64_encoded_hash(plaintext, method \\ "S256")

  def base64_encoded_hash(plaintext, _method) when not is_binary(plaintext) do
    raise ArgumentError, "ASCII content required"
  end

  def base64_encoded_hash(plaintext, method) when is_binary(method) do
    case Map.get(@supported_hash_methods, method) do
      nil ->
        raise ArgumentError, "Hash method #{method} not supported"

      crypto_method ->
        :crypto.hash(crypto_method, plaintext) |> Base.url_encode64(padding: false)
    end
  end

  # Public utility functions

  def resolve_handle_http(handle) do
    with {handle, _, _} <- normalize_handle(handle),
         url = "https://#{handle}/.well-known/atproto-did",
         {:ok, %{body: body, status: 200}} when is_binary(body) <- Req.get(url) do
      body
    else
      _ ->
        nil
    end
  end

  def resolve_handle_dns(handle) do
    with {handle, _, _} <- normalize_handle(handle),
         domain = String.to_charlist("_atproto.#{handle}"),
         {:ok, res} <- :inet_res.nslookup(domain, :in, :txt) do
      res
      |> :inet_dns.msg()
      |> Keyword.fetch!(:anlist)
      |> Enum.map(&extract_txt_data/1)
      |> List.flatten()
      |> Enum.filter(fn rr_data -> String.starts_with?(rr_data, "did=") end)
      |> Enum.map(fn rr_data -> String.replace_leading(rr_data, "did=", "") end)
      |> List.first()
    else
      _ ->
        nil
    end
  end

  defp extract_txt_data(dns_rr) do
    case :inet_dns.rr(dns_rr) |> Keyword.fetch!(:data) do
      data when is_list(data) ->
        Enum.map(data, &to_string/1)

      _ ->
        []
    end
  end

  def resolve_did(did) do
    case Cachex.get(:bluesky, "did|#{did}") do
      {:ok, document} when is_map(document) ->
        document

      _ ->
        cond do
          String.starts_with?(did, "did:plc:") ->
            resolve_did_plc(did)

          String.starts_with?(did, "did:web:") ->
            resolve_did_web(did)

          true ->
            nil
        end
    end
  end

  def resolve_did_plc(did) do
    url = "https://plc.directory/#{did}"

    with {:ok, %{body: body, status: 200}} when is_binary(body) <-
           Req.get(url, headers: [accept: "application/did+ld+json"], decode_body: false),
         {:ok, document} <- Jason.decode(body) do
      Cachex.put(:bluesky, "did|#{did}", document)
      document
    else
      _ ->
        nil
    end
  end

  def resolve_did_web(did) do
    with ["did", "web", domain] <- String.split(did, ":"),
         url = "https://#{domain}/.well-known/did.json",
         {:ok, %{body: body, status: 200}} when is_binary(body) <-
           Req.get(url, headers: [accept: "application/did+ld+json"], decode_body: false),
         {:ok, document} <- Jason.decode(body) do
      Cachex.put(:bluesky, "did|#{did}", document)
      document
    else
      _ ->
        nil
    end
  end

  def valid_did?(did) do
    Regex.match?(~r/^did:((web:.+)|(plc:[a-z2-7]{24}))$/, did)
  end

  def valid_handle?(handle) do
    case normalize_handle(handle) do
      {_, _, _} -> true
      _ -> false
    end
  end

  def normalize_handle(handle) do
    handle =
      handle
      |> String.replace_leading("@", "")
      |> String.replace_leading("at://", "")

    {username, domain} =
      case String.split(handle, ".", parts: 3) do
        [username, d1, rest] ->
          # TODO should be a Regex here
          if username != "" do
            {username, Enum.join([d1, rest], ".")}
          else
            {nil, nil}
          end

        [d1, rest] ->
          {nil, Enum.join([d1, rest], ".")}

        _ ->
          {nil, nil}
      end

    if is_binary(domain) && Regex.match?(~r/^.+\..+$/, domain) do
      {handle, username, domain}
    else
      nil
    end
  end

  def get_atproto_endpoint(did) do
    with did_document when is_map(did_document) <- resolve_did(did),
         %{"serviceEndpoint" => endpoint} <- get_atproto_service(did_document) do
      endpoint
    else
      _ ->
        nil
    end
  end

  def get_atproto_service(did_document) do
    with service_list when is_list(service_list) <- Map.get(did_document, "service"),
         atproto_service when is_map(atproto_service) <-
           Enum.find(service_list, fn service -> Map.get(service, "id") == "#atproto_pds" end) do
      atproto_service
    else
      _ ->
        nil
    end
  end

  def get_handle(%{"alsoKnownAs" => [at_handle | _]} = _did_document) do
    normalize_handle(at_handle)
  end

  def get_handle(_did_document), do: nil

  def get_authorization_server_metadata(did) when is_binary(did) do
    case resolve_did(did) do
      did_document when is_map(did_document) ->
        get_authorization_server_metadata(did_document)

      _ ->
        nil
    end
  end

  def get_authorization_server_metadata(did_document) when is_map(did_document) do
    case get_service_urls(did_document) do
      %{auth: auth_url} ->
        fetch_authorization_server_metadata(auth_url)

      _ ->
        nil
    end
  end

  def get_service_urls(did_document) when is_map(did_document) do
    with %{"serviceEndpoint" => pds_url} <- get_atproto_service(did_document),
         %{"authorization_servers" => [auth_url | _]} <-
           fetch_protected_resource_metadata(pds_url) do
      %{pds: pds_url, auth: auth_url}
    else
      _ ->
        nil
    end
  end

  def fetch_protected_resource_metadata(origin) do
    url = "#{origin}/.well-known/oauth-protected-resource"

    with {:ok, %{body: body, status: 200}} when is_binary(body) <-
           Req.get(url, headers: [accept: "application/json"], decode_body: false),
         {:ok, metadata} <- Jason.decode(body) do
      # File.write("bsky-resource-metadata.json", body)
      metadata
    else
      _ ->
        nil
    end
  end

  def fetch_authorization_server_metadata(origin) do
    case Cachex.get(:bluesky, "asmeta|#{origin}") do
      {:ok, metadata} when is_map(metadata) ->
        metadata

      _ ->
        url = "#{origin}/.well-known/oauth-authorization-server"

        with {:ok, %{body: body, status: 200}} when is_binary(body) <-
               Req.get(url, headers: [accept: "application/json"], decode_body: false),
             {:ok, metadata} <- Jason.decode(body) do
          # File.write("bsky-server-metadata.json", body)
          Cachex.put(:bluesky, "asmeta|#{origin}", metadata)
          metadata
        else
          _ ->
            nil
        end
    end
  end

  def client_metadata(scope) do
    cm_config = client_metadata_config(scope)
    origin = cm_config.base_url

    %{
      "client_name" => "Example Phoenix 1.7 atproto Browser App",
      "client_id" => cm_config.client_id,
      "scope" => scope,
      "client_uri" => origin,
      "logo_uri" => origin <> ~p"/images/logo.svg",
      "tos_uri" => origin <> ~p"/tos",
      "policy_uri" => origin <> ~p"/policy",
      "redirect_uris" => [cm_config.redirect_uri],
      "grant_types" => ["authorization_code", "refresh_token"],
      "response_types" => ["code"],
      "token_endpoint_auth_method" => "none",
      "application_type" => "web",
      "dpop_bound_access_tokens" => true
    }
  end

  def client_metadata_config(scope) do
    public_url = Sandbox.Application.public_url()

    redirect_path = ~p"/oauth/bluesky/callback"

    {client_id, redirect_uri} =
      if String.starts_with?(public_url, "http://localhost") do
        # Virtual client metadata for development client
        # See https://atproto.com/specs/oauth#clients
        host = String.replace_leading(public_url, "http://localhost", "http://127.0.0.1")
        redirect_uri = host <> redirect_path
        params = %{redirect_uri: redirect_uri, scope: scope}
        {"http://localhost/?#{URI.encode_query(params, :rfc3986)}", redirect_uri}
      else
        metadata_path = ~p"/oauth/bluesky/client-metadata.json"
        {public_url <> metadata_path, public_url <> redirect_path}
      end

    %{
      base_url: public_url,
      client_id: client_id,
      redirect_uri: redirect_uri
    }
  end

  @doc """
  Initialize a client with `client_id`, `site`, and other settings.
  For Bluesky, the `client_id` must point to a valid URL where the client metadata
  can be fetched. The client metadata will give Bluesky the `redirect_uri`
  so we don't put it in the client itself.

  In dev and test modes, we use ngrok to provide an https URL for the callback.
  """
  def client_config(did, scope) do
    case Cachex.get(:bluesky, "config|#{did}") do
      {:ok, cl_config} when is_list(cl_config) ->
        cl_config

      _ ->
        cm_config = client_metadata_config(scope)

        metadata = get_authorization_server_metadata(did)
        issuer = metadata["issuer"]
        authorize_url = metadata["authorization_endpoint"]
        token_url = metadata["token_endpoint"]
        par_url = Map.get(metadata, "pushed_authorization_request_endpoint")
        require_par? = Map.get(metadata, "require_pushed_authorization_requests", false)

        cl_config = [
          strategy: __MODULE__,
          client_id: cm_config.client_id,
          redirect_uri: cm_config.redirect_uri,
          scope: scope,
          site: issuer,
          authorize_url: authorize_url,
          token_url: token_url,
          par_url: par_url,
          subject: did,
          require_pushed_authorization_requests?: require_par?
        ]

        Cachex.put(:bluesky, "config|#{did}", cl_config)
        cl_config
    end
  end

  def put_dpop_private_jwk(client, jwk) do
    %Client{client | dpop_private_jwk: jwk}
  end

  def get_origin(url) do
    uri = URI.parse(url)
    uri = %{uri | fragment: nil, path: nil, query: nil, userinfo: nil}
    URI.to_string(uri)
  end

  @reserved_tlds ["", "local", "arpa", "internal", "localhost"]

  @doc """
  Weak security check taken from python-oauth-web-app
  """
  def safe_url?(url) do
    uri = URI.parse(url)

    if uri.scheme != "https" ||
         is_nil(uri.host) ||
         uri.host != uri.netloc ||
         !is_nil(uri.username) ||
         !is_nil(uri.password) ||
         !is_nil(uri.port) do
      false
    else
      host_parts = String.split(uri.host, ".")
      tld = List.last(host_parts)

      Enum.count(host_parts) >= 2 &&
        !(tld in @reserved_tlds) &&
        !Regex.match?(~r/^[0-9]+$/, tld)
    end
  end

  # Configures "hardened" request options
  def safe_request_options do
    [
      max_retries: 2,
      redirect: false,
      connect_options: [timeout: 2_000]
    ]
  end
end
