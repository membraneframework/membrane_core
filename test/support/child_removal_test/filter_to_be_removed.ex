defmodule Membrane.Support.ChildRemovalTest.FilterToBeRemoved do
  @moduledoc false
  use Membrane.Filter

  def_input_pad :input, accepted_format: _any, demand_mode: :auto, availability: :on_request
  def_output_pad :output, accepted_format: _any, demand_mode: :auto, availability: :on_request

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{}}
  end

  @impl true
  def handle_process(:input, buffers, _context, state) do
    {[buffer: {:output, buffers}], state}
  end
end
