defmodule SandboxWeb.MountHooks do
  use SandboxWeb, :live_view

  require Logger

  import Phoenix.LiveView

  alias Sandbox.Bluesky

  @doc """
  In router: `live_session :authenticated, on_mount: SandboxWeb.Authenticated`
  """
  def on_mount(:user, params, session, socket) do
    Logger.debug("on_mount user, session has #{inspect(session)}")
    Logger.debug("on_mount user, params are #{inspect(params)}")
    Logger.debug("on_mount user, socket.assigns are #{inspect(socket.assigns)}")

    case get_user(Map.merge(session, params)) do
      {:ok, user} ->
        Logger.debug("Assigning user")
        {:cont, assign(socket, :current_user, user)}

      {:error, reason} ->
        Logger.error("Live session user assign failed: #{reason}")
        {:halt, redirect(socket, to: ~p"/")}
    end
  end

  def on_mount(tag, params, session, socket) do
    Logger.debug("on_mount #{tag}, session has #{inspect(session)}")

    case get_user(Map.merge(session, params)) do
      {:ok, user} ->
        Logger.debug("Assigning user")
        {:cont, assign(socket, :current_user, user)}

      _ ->
        {:cont, socket}
    end
  end

  defp get_user(session) do
    case Map.get(session, "did") do
      did when is_binary(did) -> Bluesky.get_user(did)
      _ -> {:error, "No did in session"}
    end
  end
end
