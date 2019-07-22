defmodule Membrane.Support.ChildRemovalTest.Filter do
  @moduledoc """
  Module used in tests for elements removing.

  It allows to:
  * slow down the moment of switching between :prepared and :playing states.
  * deactivate demands on `input1` (useful when you want to delete element
    that is connected to this pad.
  * not send doubled `%Membrane.Event.StartOfStream{}` element
    (useful when you have two sources in a pipeline)
  * send demands and buffers from two input pads to one output pad.


  Should be used along with `Membrane.Support.ChildRemovalTest.Pipeline` as they
  share names (i.e. input_pads: `input1` and `input2`) and exchanged messages' formats.
  """

  alias Membrane.Event.StartOfStream

  use Membrane.Element.Base.Filter

  # , availability: :on_request
  def_output_pad :output, caps: :any

  # , availability: :on_request
  def_input_pad :input1, demand_unit: :buffers, caps: :any

  def_input_pad :input2, demand_unit: :buffers, caps: :any

  def_options demand_generator: [
                type: :function,
                spec: (pos_integer -> non_neg_integer),
                default: &__MODULE__.default_demand_generator/1
              ],
              target: [type: :pid],
              playing_delay: [type: :integer, default: 0],
              ref: [type: :any, default: nil],
              two_input_pads: [type: :boolean, default: false],
              sof_sent?: [type: :boolean, default: false],
              input1_deactivated: [type: :boolean, default: false]

  def deactivate_demands_on_input1(pid) do
    send(pid, {:deactivate_input1, self()})

    receive do
      :input1_deactivated ->
        :ok
    end
  end

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

  def handle_other({:deactivate_input1, caller}, _ctx, state) do
    send(caller, :input1_deactivated)
    {:ok, %{state | input1_deactivated: true}}
  end

  @impl true
  def handle_demand(:output, size, _, _ctx, state) do
    demands =
      get_demands(state, size)
      |> maybe_deactivate_input1(state)

    {{:ok, demands}, state}
  end

  @impl true
  def handle_process(:input1, buf, _, %{target: t} = state) do
    send(t, :buffer_in_filter)
    {{:ok, buffer: {:output, buf}}, state}
  end

  def handle_process(:input2, buf, _, state) do
    {{:ok, buffer: {:output, buf}}, state}
  end

  @impl true
  def handle_event(_pad, %StartOfStream{} = ev, _ctx, %{sof_sent?: false} = state) do
    {{:ok, forward: ev}, %{state | sof_sent?: true}}
  end

  def handle_event(_pad, %StartOfStream{}, _ctx, %{sof_sent?: true} = state) do
    {:ok, state}
  end

  def handle_event(_pad, event, _ctx, state) do
    {{:ok, forward: event}, state}
  end

  @impl true
  def handle_shutdown(%{target: pid}) do
    send(pid, :element_shutting_down)
    :ok
  end

  def default_demand_generator(demand), do: demand

  defp get_demands(%{two_input_pads: true} = state, size),
    do: [
      demand: {:input1, state.demand_generator.(size)},
      demand: {:input2, state.demand_generator.(size)}
    ]

  defp get_demands(state, size),
    do: [demand: {:input1, state.demand_generator.(size)}]

  defp maybe_deactivate_input1(demands, %{input1_deactivated: true}) do
    demands
    |> Enum.filter(fn {:demand, {i, _}} -> i != :input1 end)
  end

  defp maybe_deactivate_input1(demands, _) do
    demands
  end
end
