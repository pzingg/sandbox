defmodule SandboxWeb.AuthJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  def client_metadata(%{scope: scope}) do
    Sandbox.Bluesky.client_metadata(scope)
  end
end
