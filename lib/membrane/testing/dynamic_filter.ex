defmodule Membrane.Testing.DynamicFilter do
  use Membrane.Filter

  def_input_pad :input, caps: :any, demand_mode: :auto, availability: :on_request
  def_output_pad :output, caps: :any, demand_mode: :auto, availability: :on_request

  @impl true
  def handle_pad_added(pad, _ctx, state) do
    {{:ok, notify_parent: {:pad_added, pad}}, state}
  end

  @impl true
  def handle_caps(_pad, caps, _ctx, state) do
    {{:ok, forward: caps}, state}
  end

  @impl true
  def handle_event(_pad, event, _ctx, state) do
    {{:ok, forward: event}, state}
  end

  @impl true
  def handle_process(_pad, buffer, _ctx, state) do
    {{:ok, forward: buffer}, state}
  end
end
