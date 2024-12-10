defmodule SandboxWeb.SandboxLive do
  use SandboxWeb, :live_view

  alias SandboxWeb.QuoteComponent
  alias SandboxWeb.SandboxCalculatorComponent

  def mount(_params, _session, socket) do
    {:ok, assign(socket, weight: nil, price: nil)}
  end

  def render(assigns) do
    ~H"""
    <h1>Build A Sandbox</h1>

    <div id="sandbox">
      <.live_component module={SandboxCalculatorComponent} id="calc" coupon="10.0" />

      <%= if @weight do %>
        <.live_component
          module={QuoteComponent}
          id="quote1"
          title="Our Best Deal:"
          material="sand"
          weight={@weight}
          price={@price}
        />
        <.live_component
          module={QuoteComponent}
          id="quote2"
          title="Not Such a Good Deal:"
          material="sand"
          weight={@weight}
          price={@price * 2}
        />
      <% end %>
    </div>
    """
  end

  def handle_info({:totals, weight, price}, socket) do
    socket = assign(socket, weight: weight, price: price)
    {:noreply, socket}
  end
end
