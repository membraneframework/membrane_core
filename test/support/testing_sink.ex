defmodule Membrane.Integration.TestingSink do
  use Membrane.Element.Base.Sink

  def_input_pads input: [demand_in: :buffers, caps: :any]

  def_options target: [
                type: :pid
              ]

  @impl true
  def handle_init(opts) do
    {:ok, opts}
  end

  @impl true
  def handle_other({:make_demand, size}, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_write(:input, buf, _ctx, state) do
    send(state.target, buf.payload)
    {:ok, state}
  end
end
