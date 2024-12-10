defmodule SandboxWeb.BlueskyLive do
  use SandboxWeb, :live_view

  require Logger

  alias Phoenix.LiveView.AsyncResult
  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.PushedAuthRequest

  @impl true
  def mount(_params, _session, socket) do
    input = "pzingg.bsky.social"

    socket =
      socket
      |> assign(
        scope: Sandbox.Application.bluesky_client_scope(),
        input: "",
        input_type: nil,
        disabled: true,
        lookup: AsyncResult.loading("Waiting for input")
      )
      |> do_validate(input)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"handle" => input}, socket) do
    {:ok, do_validate(socket, input)}
  end

  def handle_event("authorize", _params, socket) do
    %{scope: scope, input: input, input_type: type, lookup: lookup} = socket.assigns

    did =
      case type do
        :did -> input
        :handle -> Map.get(lookup.result, :did)
      end

    socket =
      case Bluesky.authorization_flow(did, scope) do
        {:ok, %PushedAuthRequest{client: client, authorize_params: params}} ->
          authorize_url = Bluesky.authorize_url!(client, params)
          Logger.info("redirecting to #{inspect(authorize_url)}")
          redirect(socket, external: authorize_url)

        {:error, reason} ->
          put_flash(socket, :error, reason)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:lookup, {:ok, {:ok, result}}, socket) do
    %{lookup: lookup} = socket.assigns
    {:noreply, assign(socket, disabled: false, lookup: AsyncResult.ok(lookup, result))}
  end

  def handle_async(:lookup, {:ok, {:error, reason}}, socket) do
    %{lookup: lookup} = socket.assigns

    {:noreply,
     assign(socket, disabled: true, lookup: AsyncResult.failed(lookup, to_string(reason)))}
  end

  def handle_async(:lookup, {:exit, reason}, socket) do
    %{lookup: lookup} = socket.assigns

    {:noreply,
     assign(socket, disabled: true, lookup: AsyncResult.failed(lookup, to_string(reason)))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Log into your Bluesky server</h1>
    <div id="sandbox">
      <form phx-change="validate" phx-submit="authorize">
        <div class="field">
          <label for="length">Handle or DID:</label>
          <input type="text" name="handle" value={@input} />
        </div>
        <div>{show_lookup(@lookup)}</div>
        <button disabled={@disabled}>
          Authorize
        </button>
      </form>
    </div>
    """
  end

  def do_validate(socket, input) do
    socket =
      cond do
        Bluesky.valid_did?(input) ->
          socket
          |> assign(input_type: :did, lookup: AsyncResult.loading("Looking up that DID..."))
          |> start_async(:lookup, fn -> lookup_did(input) end)

        Bluesky.valid_handle?(input) ->
          socket
          |> assign(input_type: :handle, lookup: AsyncResult.loading("Looking up that handle..."))
          |> start_async(:lookup, fn -> lookup_handle(input) end)

        input != "" ->
          assign(socket,
            input_type: :invalid,
            lookup: AsyncResult.loading("Not a valid handle or DID")
          )

        true ->
          assign(socket, input_type: nil, lookup: AsyncResult.loading("Waiting for input"))
      end

    assign(socket, :input, input)
  end

  def show_lookup(lookup) do
    cond do
      lookup.loading -> lookup.loading
      lookup.failed -> "Failed #{lookup.failed}"
      true -> lookup.result.message
    end
  end

  defp lookup_did(did) do
    case Bluesky.resolve_did(did) do
      %{"alsoKnownAs" => [at_handle | _]} ->
        case Bluesky.normalize_handle(at_handle) do
          {handle, _, _} -> {:ok, %{handle: handle, message: "Found handle: #{handle}"}}
          _ -> {:error, "Internal error"}
        end

      _ ->
        {:error, "Unable to resolve DID"}
    end
  end

  defp lookup_handle(handle) do
    case Bluesky.resolve_handle_http(handle) do
      did when is_binary(did) ->
        {:ok, %{did: did, message: "Found did: #{did}"}}

      _ ->
        {:error, "Unable to resolve DID"}
    end
  end
end
