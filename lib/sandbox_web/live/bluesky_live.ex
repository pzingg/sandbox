defmodule SandboxWeb.BlueskyLive do
  use SandboxWeb, :live_view

  require Logger

  alias Phoenix.LiveView.AsyncResult
  alias Sandbox.Bluesky
  alias Sandbox.Bluesky.AuthRequestData

  @impl true
  def mount(_params, _session, socket) do
    input = "pzingg.bsky.social"
    scope = Sandbox.Application.bluesky_client_scope()

    socket =
      socket
      |> assign(
        page_title: "Sign in to Bluesky",
        scope: scope,
        input: "",
        input_type: nil,
        disabled: true,
        lookup: AsyncResult.loading("Waiting for input")
      )
      |> do_validate(input, scope)

    {:ok, socket}
  end

  @impl true
  def handle_event(
        "validate",
        %{"_target" => target, "handle" => input, "scope" => scope},
        socket
      ) do
    {:noreply, do_validate(socket, input, scope, target)}
  end

  def handle_event("authorize", _params, socket) do
    %{scope: scope, input: input, input_type: type, lookup: lookup} = socket.assigns

    did =
      case type do
        :did -> input
        :handle -> Map.get(lookup.result, :did)
      end

    socket =
      case Bluesky.pushed_authorization_request(did, scope: scope) do
        {:ok, %AuthRequestData{} = request_data} ->
          authorize_url = Bluesky.authorize_url!(request_data)
          redirect(socket, external: authorize_url)

        {:error, reason} ->
          put_flash(socket, :error, reason)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:lookup, {:ok, {:ok, result}}, socket) do
    %{lookup: lookup} = socket.assigns

    socket =
      socket
      |> assign(:lookup, AsyncResult.ok(lookup, result))
      |> assign_disabled()

    {:noreply, socket}
  end

  def handle_async(:lookup, {:ok, {:error, reason}}, socket) do
    %{lookup: lookup} = socket.assigns

    socket =
      socket
      |> assign(:lookup, AsyncResult.failed(lookup, to_string(reason)))
      |> assign_disabled(true)

    {:noreply, socket}
  end

  def handle_async(:lookup, {:exit, reason}, socket) do
    %{lookup: lookup} = socket.assigns

    socket =
      socket
      |> assign(:lookup, AsyncResult.failed(lookup, to_string(reason)))
      |> assign_disabled(true)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Sign in to your Bluesky server</h1>
    <div id="sandbox">
      <form phx-change="validate" phx-submit="authorize">
        <div class="field">
          <label for="length">Handle or DID</label>
          <input type="text" name="handle" value={@input} />
        </div>
        <div class="field">
          <label for="scope">Scope</label>
          <input type="text" name="scope" value={@scope} />
        </div>
        <div class="flex items-center pt-2">
          <div class="flex-1 block w-full">{show_lookup(@lookup)}</div>
        </div>
        <div class="flex pb-2">
          <div class="flex justify-center w-full">
            <button class="button" type="submit" disabled={@disabled}>
              Sign in
            </button>
          </div>
        </div>
      </form>
    </div>
    """
  end

  def do_validate(socket, input, scope, target \\ :all) do
    input_changed? = target == :all || "handle" in target

    socket =
      cond do
        !input_changed? ->
          socket

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

    socket
    |> assign(:input, input)
    |> assign(:scope, scope)
    |> assign_disabled()
  end

  def assign_disabled(socket, value \\ nil) do
    disabled =
      if is_nil(value) do
        %{scope: scope, lookup: lookup} = socket.assigns
        !valid_scope?(scope) || lookup.loading || lookup.failed
      else
        !!value
      end

    assign(socket, :disabled, disabled)
  end

  @bs_scopes ["atproto", "transition:generic"]

  defp valid_scope?(scope) do
    scopes = Regex.split(~r/\s+/, scope)
    "atproto" in scopes && Enum.all?(scopes, fn scope -> scope in @bs_scopes end)
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
