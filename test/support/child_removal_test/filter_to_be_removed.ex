defmodule Membrane.Support.ChildRemovalTest.FilterToBeRemoved do
  @moduledoc false
  use Membrane.Filter

  def_input_pad :input, caps: :any, demand_mode: :auto
  def_output_pad :output, caps: :any, demand_mode: :auto

  @impl true
  def handle_init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_process(:input, buffers, _context, state) do
    {{:ok, buffer: {:output, buffers}}, state}
  end
end
