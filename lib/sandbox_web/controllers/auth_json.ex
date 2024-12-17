defmodule SandboxWeb.AuthJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  def client_metadata(%{scope: scope}) do
    Sandbox.Bluesky.client_metadata(scope)
  end

  def jwks(_assigns) do
    {_private_map, public_map} = Sandbox.Bluesky.get_private_jwk("__client__") |> OAuth2.JWK.to_maps()
    %{"keys" => public_map}
  end
end
