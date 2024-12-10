defmodule SandboxWeb.QuoteComponent do
  use SandboxWeb, :live_component

  import Number.Currency

  def mount(socket) do
    {:ok, assign(socket, hrs_until_expires: 24)}
  end

  # def update(assigns, socket) do
  #   {:ok, assign(socket, assigns)}
  # end

  def render(assigns) do
    ~H"""
    <div phx-target={@myself} phx-click="click-me" class="p-6 my-4 text-center border-4 border-indigo-600 border-dashed">
      <h2 class="mb-2 text-2xl">
        <%= @title %>
      </h2>
      <h3 class="text-xl font-semibold text-indigo-600">
        <%= @weight %> pounds of <%= @material %>
        for <%= number_to_currency(@price) %>
      </h3>
      <div class="text-gray-600">
        expires in <%= @hrs_until_expires %> hours
      </div>
    </div>
    """
  end

  def handle_event("click-me", _params, socket) do
    hrs_until_expires = socket.assigns.hrs_until_expires + 24
    {:noreply, assign(socket, hrs_until_expires: hrs_until_expires)}
  end
end
