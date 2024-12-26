defmodule Sandbox.BlueskyTest do
  use ExUnit.Case, async: true

  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.AuthRequestData

  test "public url" do
    url = Sandbox.Application.public_url()
    assert url == "http://localhost:4002" || Regex.match?(~r/^https:\/\/.+\.ngrok.*\.app$/, url)
  end

  test "normalizes handle with prefix" do
    assert {"pzingg.bsky.social", "pzingg", "bsky.social"} =
             Bluesky.normalize_handle("at://pzingg.bsky.social")
  end

  test "normalizes bare handle" do
    assert {"pzingg.bsky.social", "pzingg", "bsky.social"} =
             Bluesky.normalize_handle("pzingg.bsky.social")
  end

  test "normalizes domain handle" do
    assert {"bipeds.onl", nil, "bipeds.onl"} = Bluesky.normalize_handle("bipeds.onl")
  end

  test "invalid domain handle" do
    assert Bluesky.normalize_handle("bipeds") == nil
  end

  test "invalid handle" do
    assert Bluesky.normalize_handle(".bipeds.onl") == nil
  end

  test "resolves handle by dns" do
    handle = "bipeds.onl"
    did = Bluesky.resolve_handle_dns(handle)
    assert did == "did:plc:mfv6fysngq5fkoiqozzlv642"
  end

  test "resolves handle by http" do
    handle = "pzingg.bsky.social"
    did = Bluesky.resolve_handle_http(handle)
    assert did == "did:plc:mfv6fysngq5fkoiqozzlv642"
  end

  test "resolves did:plc" do
    did = "did:plc:mfv6fysngq5fkoiqozzlv642"
    did_document = Bluesky.resolve_did(did)
    assert is_map(did_document)
    assert did_document["id"] == did
    assert {handle, _, _} = Bluesky.get_handle(did_document)
    assert handle == "pzingg.bsky.social"
    did_for_handle = Bluesky.resolve_handle_http(handle)
    assert did_for_handle == did
    atproto_service = Bluesky.get_atproto_service(did_document)
    assert is_map(atproto_service)
  end

  # bipeds.onl not yet configured to serve /.well-known/did.json
  @tag :skip
  test "resolves did:web" do
    did = "did:web:bipeds.onl"
    did_document = Bluesky.resolve_did(did)
    assert is_map(did_document)
    assert did_document["id"] == did
    assert {"pzingg.bsky.social", _, _} = Bluesky.get_handle(did_document)
  end

  test "ES256" do
    private_key_assertions("ES256")
  end

  test "ES256K" do
    private_key_assertions("ES256K")
  end

  test "RS256" do
    private_key_assertions("RS256")
  end

  test "PS256" do
    private_key_assertions("PS256")
  end

  def private_key_assertions(alg) do
    jwk = OAuth2.JWK.generate_key!(alg)
    {private_map, public_map} = OAuth2.JWK.to_maps(jwk)
    assert private_map["alg"] == alg
    refute public_map["d"]
    refute public_map["alg"]
    bin = JOSE.JWK.to_binary(jwk)
    assert JOSE.JWK.from_binary(bin) == jwk
    json = OAuth2.JWK.to_json(jwk)
    assert {:ok, ^jwk} = OAuth2.JWK.from_json(json)
  end

  test "gets PDS bsky.network protected resource metadata" do
    did = "did:plc:mfv6fysngq5fkoiqozzlv642"
    did_document = Bluesky.resolve_did(did)
    assert is_map(did_document)
    assert %{"serviceEndpoint" => origin} = Bluesky.get_atproto_service(did_document)
    metadata = Bluesky.fetch_protected_resource_metadata(origin)
    assert is_map(metadata)
    assert metadata["resource"] == origin
    assert "https://bsky.social" in metadata["authorization_servers"]
  end

  test "gets bsky.social authorization server metadata" do
    metadata = Bluesky.fetch_authorization_server_metadata("https://bsky.social")
    assert is_map(metadata)
    assert metadata["issuer"] == "https://bsky.social"
    assert metadata["authorization_endpoint"] == "https://bsky.social/oauth/authorize"
    assert metadata["token_endpoint"] == "https://bsky.social/oauth/token"
    assert metadata["pushed_authorization_request_endpoint"] == "https://bsky.social/oauth/par"
    assert "ES256" in metadata["dpop_signing_alg_values_supported"]
    assert "atproto" in metadata["scopes_supported"]
    assert "transition:generic" in metadata["scopes_supported"]
  end

  test "finds authorization server from did" do
    did = "did:plc:mfv6fysngq5fkoiqozzlv642"
    did_document = Bluesky.resolve_did(did)
    assert is_map(did_document)
    assert did_document["id"] == did
    metadata = Bluesky.get_authorization_server_metadata(did_document)
    assert is_map(metadata)
    assert metadata["issuer"] == "https://bsky.social"
  end

  test "gets client metadata" do
    client_id =
      Bluesky.client_metadata_config("atproto transition:generic") |> Map.fetch!(:client_id)

    if String.starts_with?(client_id, "http://localhost") do
      %URI{query: query} = URI.parse(client_id)
      params = URI.decode_query(query, %{}, :rfc3986)
      assert params["redirect_uri"] == "http://127.0.0.1:4002/oauth/bluesky/callback"
    else
      assert {:ok, resp} = Req.get(client_id)
      assert resp.status == 200
      assert resp.body["client_id"] == client_id
    end
  end

  test "makes a DPoP token" do
    jwk = OAuth2.JWK.generate_key!("ES256")
    assert OAuth2.JWK.private_key_with_signer?(jwk)
    url = "http://localhost"
    nonce = Bluesky.generate_nonce(64)

    assert {:ok, {_token, header, claims}} =
             OAuth2.DPoP.proof(jwk, url, method: :post, nonce: nonce)

    assert header["alg"] == "ES256"
    assert claims["nonce"] == nonce
  end

  test "configures client for PAR" do
    did = "did:plc:mfv6fysngq5fkoiqozzlv642"
    params = [test_only: true, login_hint: "pzingg.bsky.social"]

    assert {:ok, %AuthRequestData{request_headers: headers}} =
             Bluesky.pushed_authorization_request(did, params)

    assert {"DPoP", _token} = List.keyfind(headers, "DPoP", 0)
  end

  test "makes PAR request and authorize request" do
    did = "did:plc:mfv6fysngq5fkoiqozzlv642"
    params = [login_hint: "pzingg.bsky.social"]

    assert {:ok, %AuthRequestData{authorize_params: params}} =
             Bluesky.pushed_authorization_request(did, params)

    assert is_binary(params[:request_uri])
    assert String.starts_with?(params[:request_uri], "urn:ietf:params:oauth:request_uri:")
  end

  test "makes an unauthenticated xrpc query" do
    server = "https://public.api.bsky.app"
    did = "did:plc:mfv6fysngq5fkoiqozzlv642"
    params = [actor: did]

    assert {:ok, response} =
             Bluesky.xrpc_request(:get, server, "app.bsky.actor.getProfile", params)

    assert response.body["did"] == did
    assert response.body["handle"] == "pzingg.bsky.social"
  end
end
