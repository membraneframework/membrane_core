defmodule Membrane.Support.ChildRemovalTest.Filter do
  @moduledoc false
  use Membrane.Element.Base.Filter

  # , availability: :on_request
  def_output_pad :output, caps: :any

  # , availability: :on_request
  def_input_pad :input, demand_unit: :buffers, caps: :any

  def_options demand_generator: [
                type: :function,
                spec: (pos_integer -> non_neg_integer),
                default: &__MODULE__.default_demand_generator/1
              ],
              target: [type: :pid],
              playing_delay: [type: :integer, default: 0],
              ref: [type: :any, default: nil]

  @impl true
  def handle_init(%{target: t, ref: ref} = opts) do
    send(t, {:filter_pid, ref, self()})
    {:ok, opts}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, %{playing_delay: 0} = state) do
    {:ok, state}
  end

  def handle_prepared_to_playing(_ctx, %{playing_delay: time} = state) do
    :timer.send_after(time, self(), :resume_after_wait)
    {{:ok, playback_change: :suspend}, state}
  end

  @impl true
  def handle_other(:resume_after_wait, _ctx, state) do
    {{:ok, playback_change: :resume}, state}
  end

  @impl true
  def handle_demand(:output, size, _, _ctx, state) do
    {{:ok, demand: {:input, state.demand_generator.(size)}}, state}
  end

  @impl true
  def handle_process(:input, buf, _, %{target: t} = state) do
    send(t, :buffer_in_filter)
    {{:ok, buffer: {:output, buf}, redemand: :output}, state}
  end

  @impl true
  def handle_shutdown(%{target: pid}) do
    send(pid, :element_shutting_down)
    :ok
  end

  def default_demand_generator(demand), do: demand
end
