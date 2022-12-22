defmodule Membrane.Integration.DeferSetupTest do
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Pad
  alias Membrane.Testing.{Pipeline, Sink, Source}

  defmodule Bin do
    use Membrane.Bin

    def_input_pad :input,
      demand_unit: :buffers,
      accepted_format: _any,
      availability: :on_request,
      demand_mode: :manual

    def_output_pad :output,
      demand_unit: :buffers,
      accepted_format: _any,
      availability: :on_request,
      demand_mode: :manual

    def_options defer_play: [spec: boolean(), default: true],
                specs_list: [spec: list(), default: []]

    @impl true
    def handle_init(_ctx, opts) do
      state = Map.from_struct(opts)
      actions = Enum.map(state.specs_list, &{:spec, &1})
      {actions, state}
    end

    @impl true
    def handle_setup(_ctx, state) do
      actions = if state.defer_play, do: [setup: :incomplete], else: []
      {actions, state}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[notify_parent: :handle_playing], state}
    end

    @impl true
    def handle_parent_notification(:complete_setup, _ctx, state) do
      {[setup: :complete], state}
    end

    @impl true
    def handle_parent_notification({:complete_setup, child}, _ctx, state) do
      {[notify_child: {child, :complete_setup}], state}
    end

    @impl true
    def handle_child_notification(_notification, Pad.ref(_name, _ref), _ctx, state) do
      {[], state}
    end

    @impl true
    def handle_child_notification(:handle_playing, child, _ctx, state) do
      {[notify_parent: {child, :handle_playing}], state}
    end

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      spec =
        case pad do
          Pad.ref(:input, _ref) ->
            bin_input(pad) |> child(pad, Sink)

          Pad.ref(:output, _ref) ->
            child(pad, Source) |> bin_output(pad)
        end

      {[spec: spec], state}
    end

    @impl true
    def handle_pad_removed(pad, _ctx, state) do
      {[remove_children: pad], state}
    end
  end

  test "[setup: :incomplete] and [setup: :complete]" do
    pipeline =
      Pipeline.start_supervised!(
        spec:
          child(:bin_1, %Bin{
            specs_list: [
              child(:bin_a, Bin),
              child(:bin_b, Bin)
              |> child(:bin_c, Bin)
            ]
          })
          |> child(:bin_2, %Bin{defer_play: false})
      )

    assert_pipeline_play(pipeline)

    for bin <- [:bin_1, :bin_2] do
      refute_child_playing(pipeline, bin)
    end

    for bin <- [:bin_a, :bin_b, :bin_c] do
      refute_grandhild_playing(pipeline, :bin_1, bin)
    end

    complete_grandchild_setup(pipeline, :bin_1, :bin_a)

    refute_grandhild_playing(pipeline, :bin_1, :bin_a)

    refute_child_playing(pipeline, :bin_1)
    complete_child_setup(pipeline, :bin_1)

    for bin <- [:bin_1, :bin_2] do
      assert_child_playing(pipeline, bin)
    end

    assert_grandhild_playing(pipeline, :bin_1, :bin_a)

    for bin <- [:bin_b, :bin_c] do
      refute_grandhild_playing(pipeline, :bin_1, bin)
    end

    complete_grandchild_setup(pipeline, :bin_1, :bin_b)

    for bin <- [:bin_b, :bin_c] do
      refute_grandhild_playing(pipeline, :bin_1, bin)
    end

    complete_grandchild_setup(pipeline, :bin_1, :bin_c)

    for bin <- [:bin_b, :bin_c] do
      assert_grandhild_playing(pipeline, :bin_1, bin)
    end

    monitor_ref = Process.monitor(pipeline)
    complete_child_setup(pipeline, :bin_2)
    assert_receive {:DOWN, ^monitor_ref, :process, ^pipeline, {:shutdown, :child_crash}}
  end

  defp complete_child_setup(pipeline, child) do
    Pipeline.execute_actions(pipeline, notify_child: {child, :complete_setup})
  end

  defp complete_grandchild_setup(pipeline, child, grandchild) do
    Pipeline.execute_actions(pipeline, notify_child: {child, {:complete_setup, grandchild}})
  end

  defp assert_child_playing(pipeline, child) do
    assert_pipeline_notified(pipeline, child, :handle_playing)
  end

  defp assert_grandhild_playing(pipeline, child, grandchild) do
    assert_pipeline_notified(pipeline, child, {^grandchild, :handle_playing})
  end

  defp refute_child_playing(pipeline, child) do
    refute_pipeline_notified(pipeline, child, :handle_playing)
  end

  defp refute_grandhild_playing(pipeline, child, grandchild) do
    refute_pipeline_notified(pipeline, child, {^grandchild, :handle_playing})
  end
end
