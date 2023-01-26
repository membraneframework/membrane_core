defmodule Membrane.Integration.ChildPadRemovedTest do
  use ExUnit.Case, async: false

  alias Membrane.Testing

  require Membrane.Pad, as: Pad

  defmodule DynamicSource do
    use Membrane.Source
    def_output_pad :output, flow_control: :push, availability: :on_request, accepted_format: _any
  end

  defmodule DynamicSink do
    use Membrane.Sink
    def_input_pad :input, flow_control: :push, availability: :on_request, accepted_format: _any
    def_options test_process: [spec: pid()]

    @impl true
    def handle_init(ctx, opts) do
      send(opts.test_process, {:init, ctx.name})
      {[], Map.from_struct(opts)}
    end

    @impl true
    def handle_pad_added(_pad, ctx, state) do
      send(state.test_process, {:pad_added, ctx.name})
      {[], state}
    end

    @impl true
    def handle_pad_removed(_pad, ctx, state) do
      send(state.test_process, {:pad_removed, ctx.name})
      {[], state}
    end
  end

  defmodule StaticSink do
    use Membrane.Sink
    def_input_pad :input, flow_control: :push, accepted_format: _any
    def_options test_process: [spec: pid()]

    @impl true
    def handle_init(ctx, opts) do
      send(opts.test_process, {:init, ctx.name})
      {[], Map.from_struct(opts)}
    end
  end

  defmodule DynamicBin do
    use Membrane.Bin

    require Membrane.Pad, as: Pad

    def_output_pad :output, availability: :on_request, accepted_format: _any
    def_options test_process: [spec: pid()]

    @impl true
    def handle_parent_notification({:execute_actions, actions}, _ctx, state) do
      {actions, state}
    end

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      spec =
        child(:source, DynamicSource)
        |> via_out(Pad.ref(:output, 1))
        |> bin_output(pad)

      {[spec: spec], state}
    end
  end

  defmodule Pipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, opts) do
      %{bin: bin, sink: sink, actions_on_child_removed_pad: actions, test_process: test_process} =
        Map.new(opts)

      spec = child(:bin, bin) |> child(:sink, sink)
      {[spec: spec], %{actions: actions, test_process: test_process}}
    end

    @impl true
    def handle_info({:execute_actions, actions}, _ctx, state) do
      {actions, state}
    end

    @impl true
    def handle_child_pad_removed(:bin, pad, _ctx, %{actions: actions} = state) do
      send(state.test_process, {:child_pad_removed, :bin, pad})
      {actions, state}
    end
  end

  defp start_pipeline!(bin, sink, actions_on_child_removed_pad \\ []) do
    do_start_pipeline!(:start, bin, sink, actions_on_child_removed_pad)
  end

  defp start_link_pipeline!(bin, sink, actions_on_child_removed_pad \\ []) do
    do_start_pipeline!(:start_link, bin, sink, actions_on_child_removed_pad)
  end

  defp do_start_pipeline!(function, bin, sink, actions) do
    args = [
      Pipeline,
      [
        bin: struct(bin, test_process: self()),
        sink: struct(sink, test_process: self()),
        actions_on_child_removed_pad: actions,
        test_process: self()
      ]
    ]

    {:ok, _supervisor, pipeline} = apply(Membrane.Pipeline, function, args)

    pipeline
  end

  defp execute_actions_in_bin(pipeline, actions) do
    msg_to_bin = {:execute_actions, actions}
    msg_to_pipeline = {:execute_actions, notify_child: {:bin, msg_to_bin}}
    send(pipeline, msg_to_pipeline)
  end

  defp assert_child_exists(pipeline, child_ref_path) do
    assert {:ok, pid} = Testing.Pipeline.get_child_pid(pipeline, child_ref_path)
    assert is_pid(pid)
  end

  describe "when child-bin removes a pad" do
    test "sibling is unlinked" do
      for bin_actions <- [
            [remove_children: :source],
            [remove_link: {:source, Pad.ref(:output, 1)}]
          ] do
        pipeline = start_link_pipeline!(DynamicBin, DynamicSink)

        execute_actions_in_bin(pipeline, bin_actions)

        receive do
          {:pad_added, :sink} ->
            assert_receive {:pad_removed, :sink}
        after
          500 ->
            refute_received {:pad_removed, :sink}
        end

        assert_receive {:child_pad_removed, :bin, Pad.ref(:output, _id)}
        assert_child_exists(pipeline, :bin)
        assert_child_exists(pipeline, :sink)

        Pipeline.terminate(pipeline, blocking?: true)
      end
    end

    test "sibling linked via static pad raises" do
      for actions <- [
            [remove_children: :source],
            [remove_link: {:source, Pad.ref(:output, 1)}]
          ] do
        pipeline = start_pipeline!(DynamicBin, StaticSink)

        assert_receive {:init, :sink}
        sink_pid = Testing.Pipeline.get_child_pid!(pipeline, :sink)
        monitor_ref = Process.monitor(sink_pid)

        execute_actions_in_bin(pipeline, actions)

        assert_receive {:child_pad_removed, :bin, Pad.ref(:output, _id)}

        assert_receive {:DOWN, ^monitor_ref, :process, ^sink_pid,
                        {%Membrane.PadError{message: message}, _stacktrace}}

        assert message =~ ~r/Tried.*to.*unlink.*a.*static.*pad.*input.*/
      end
    end

    @tag :target
    test "and sibling linked via static pad is removed, pipeline is not raising" do
      for bin_actions <- [
            [remove_children: :source],
            [remove_link: {:source, Pad.ref(:output, 1)}]
          ] do
        pipeline = start_link_pipeline!(DynamicBin, StaticSink, remove_children: :sink)

        assert_receive {:init, :sink}
        sink_pid = Testing.Pipeline.get_child_pid!(pipeline, :sink)
        monitor_ref = Process.monitor(sink_pid)

        execute_actions_in_bin(pipeline, bin_actions)

        assert_receive {:child_pad_removed, :bin, Pad.ref(:output, _id)}
        assert_receive {:DOWN, ^monitor_ref, :process, ^sink_pid, _reason}
        assert_child_exists(pipeline, :bin)

        Pipeline.terminate(pipeline, blocking?: true)
      end
    end
  end
end
