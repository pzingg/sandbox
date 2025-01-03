defmodule SandboxWeb.PageLive do
  use SandboxWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Home")
      |> reset_query()

    {:ok, socket}
  end

  @impl true
  def handle_event("suggest", %{"q" => query}, socket) do
    results = search(query)
    lookup_button_disabled = Enum.empty?(results)

    {:noreply,
     assign(socket,
       query: query,
       results: results,
       lookup_button_disabled: lookup_button_disabled
     )}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    case search(query) do
      %{^query => vsn} ->
        {:noreply, redirect(socket, external: "https://hexdocs.pm/#{query}/#{vsn}")}

      _ ->
        socket =
          socket
          |> put_flash(:error, "No dependencies found matching \"#{query}\"")
          |> reset_query()

        {:noreply, socket}
    end
  end

  defp search(query) do
    if not SandboxWeb.Endpoint.config(:code_reloader) do
      raise "action disabled when not in development"
    end

    for {app, desc, vsn} <- Application.started_applications(),
        app = to_string(app),
        String.starts_with?(app, query) and not List.starts_with?(desc, ~c"ERTS"),
        into: %{},
        do: {app, vsn}
  end

  defp reset_query(socket) do
    assign(socket,
      query: "",
      results: %{},
      lookup_button_disabled: true
    )
  end
end
