defmodule Membrane.Integration.CuttingLinksTest do
  use Bunch
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  require Membrane.Pad, as: Pad

  defmodule Macros do
    defmacro notify_on_playing() do
      quote do
        @impl true
        def handle_playing(_ctx, state) do
          {[notify_parent: :playing], state}
        end
      end
    end

    defmacro notify_on_pad_removed() do
      quote do
        @impl true
        def handle_pad_removed(pad, _ctx, state) do
          {[notify_parent: {:pad_removed, pad}], state}
        end
      end
    end

    defmacro forward_child_notification() do
      quote do
        @impl true
        def handle_child_notification(msg, child, _ctx, state) do
          {[notify_parent: {:child_notification, child, msg}], state}
        end
      end
    end
  end

  defmodule DynamicElement do
    use Membrane.Endpoint
    require Membrane.Integration.CuttingLinksTest.Macros, as: Macros

    def_input_pad :input, accepted_format: _any, flow_control: :push, availability: :on_request
    def_output_pad :output, accepted_format: _any, flow_control: :push, availability: :on_request

    Macros.notify_on_playing()
    Macros.notify_on_pad_removed()
  end

  defmodule StaticSource do
    use Membrane.Source
    def_output_pad :output, accepted_format: _any, flow_control: :push
  end

  defmodule StaticSink do
    use Membrane.Sink
    def_input_pad :input, accepted_format: _any, flow_control: :push
  end

  defmodule DynamicBin do
    use Membrane.Bin
    require Membrane.Integration.CuttingLinksTest.Macros, as: Macros

    def_input_pad :input, accepted_format: _any, availability: :on_request
    def_output_pad :output, accepted_format: _any, availability: :on_request

    Macros.notify_on_playing()
    Macros.notify_on_pad_removed()
    Macros.forward_child_notification()

    @impl true
    def handle_init(_ctx, state) do
      {[spec: child(:element, DynamicElement)], state}
    end

    @impl true
    def handle_pad_added(Pad.ref(direction, _id) = pad, _ctx, state) do
      spec =
        case direction do
          :input -> bin_input(pad) |> get_child(:element)
          :output -> get_child(:element) |> bin_output(pad)
        end

      {[spec: spec], state}
    end
  end

  defmodule NestedBin do
    use Membrane.Bin
    require Membrane.Integration.CuttingLinksTest.Macros, as: Macros

    def_input_pad :input, accepted_format: _any, availability: :on_request

    Macros.notify_on_playing()
    Macros.notify_on_pad_removed()
    Macros.forward_child_notification()

    @impl true
    def handle_init(_ctx, state) do
      {[spec: child(:inner_bin, DynamicBin)], state}
    end

    @impl true
    def handle_pad_added(Pad.ref(:input, _id) = pad, _ctx, state) do
      spec =
        bin_input(pad)
        |> via_in(pad, implicit_unlink?: false)
        |> get_child(:inner_bin)

      {[spec: spec], state}
    end
  end

  describe "cutting link between 2 elements" do
    test "with dynamic pads" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:source, DynamicElement)
            |> via_in(Pad.ref(:input, 1), implicit_unlink?: false)
            |> child(:sink, DynamicElement)
        )

      assert_pipeline_notified(pipeline, :source, :playing)
      assert_pipeline_notified(pipeline, :sink, :playing)

      Testing.Pipeline.execute_actions(pipeline, remove_children: :source)
      refute_pipeline_notified(pipeline, :sink, {:pad_removed, _pad})

      Testing.Pipeline.execute_actions(pipeline, remove_child_pad: {:sink, Pad.ref(:input, 1)})
      assert_pipeline_notified(pipeline, :sink, {:pad_removed, Pad.ref(:input, 1)})

      Testing.Pipeline.terminate(pipeline)
    end

    test "when `source` side has a static pad" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:source, StaticSource)
            |> via_in(Pad.ref(:input, 1), implicit_unlink?: false)
            |> child(:sink, DynamicElement)
        )

      assert_pipeline_notified(pipeline, :sink, :playing)

      Testing.Pipeline.execute_actions(pipeline, remove_children: :source)
      refute_pipeline_notified(pipeline, :sink, {:pad_removed, _pad})

      Testing.Pipeline.execute_actions(pipeline, remove_child_pad: {:sink, Pad.ref(:input, 1)})
      assert_pipeline_notified(pipeline, :sink, {:pad_removed, Pad.ref(:input, 1)})

      Testing.Pipeline.terminate(pipeline)
    end

    test "when `sink` side has a static pad" do
      pipeline =
        Testing.Pipeline.start_supervised!(
          spec:
            child(:source, DynamicElement)
            |> via_out(Pad.ref(:output, 1))
            |> via_in(:input, implicit_unlink?: false)
            |> child(:sink, StaticSink)
        )

      assert_pipeline_notified(pipeline, :source, :playing)

      sink_pid = Testing.Pipeline.get_child_pid!(pipeline, :sink)
      sink_monitor = Process.monitor(sink_pid)

      Testing.Pipeline.execute_actions(pipeline, remove_child_pad: {:source, Pad.ref(:output, 1)})
      refute_receive {:DOWN, ^sink_monitor, :process, ^sink_pid, _reason}

      pipeline_monitor = Process.monitor(pipeline)
      Testing.Pipeline.execute_actions(pipeline, remove_child_pad: {:sink, :input})

      assert_receive {:DOWN, ^pipeline_monitor, :process, ^pipeline, {:shutdown, :child_crash}}
    end
  end

  test "cutting link between 2 bins with dynamic pads" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec:
          child(:source_bin, DynamicBin)
          |> via_in(Pad.ref(:input, 1), implicit_unlink?: false)
          |> child(:sink_bin, DynamicBin)
      )

    assert_pipeline_notified(pipeline, :source_bin, :playing)
    assert_pipeline_notified(pipeline, :source_bin, {:child_notification, :element, :playing})
    assert_pipeline_notified(pipeline, :sink_bin, :playing)
    assert_pipeline_notified(pipeline, :sink_bin, {:child_notification, :element, :playing})

    Testing.Pipeline.execute_actions(pipeline, remove_children: :source_bin)
    refute_pipeline_notified(pipeline, :sink_bin, {:pad_removed, _pad})

    refute_pipeline_notified(
      pipeline,
      :sink_bin,
      {:child_notification, :element, {:pad_removed, _pad}}
    )

    Testing.Pipeline.execute_actions(pipeline, remove_child_pad: {:sink_bin, Pad.ref(:input, 1)})
    assert_pipeline_notified(pipeline, :sink_bin, {:pad_removed, Pad.ref(:input, 1)})

    assert_pipeline_notified(
      pipeline,
      :sink_bin,
      {:child_notification, :element, {:pad_removed, Pad.ref(:input, _id)}}
    )

    Testing.Pipeline.terminate(pipeline)
  end

  describe "cutting link between bin's child and bin's pad" do
    test "triggered by unlinking bin" do
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:element, DynamicElement)
            |> via_out(Pad.ref(:output, 1))
            |> via_in(Pad.ref(:input, 1))
            |> child(:bin, NestedBin)
        )

      assert_pipeline_notified(pipeline, :element, :playing)
      assert_pipeline_notified(pipeline, :bin, :playing)
      assert_pipeline_notified(pipeline, :bin, {:child_notification, :inner_bin, :playing})

      assert_pipeline_notified(
        pipeline,
        :bin,
        {:child_notification, :inner_bin, {:child_notification, :element, :playing}}
      )

      Testing.Pipeline.execute_actions(pipeline, remove_child_pad: {:element, Pad.ref(:output, 1)})

      assert_pipeline_notified(pipeline, :bin, {:pad_removed, Pad.ref(:input, 1)})

      refute_pipeline_notified(
        pipeline,
        :bin,
        {:child_notification, :inner_bin, {:pad_removed, _pad}}
      )

      refute_pipeline_notified(
        pipeline,
        :bin,
        {:child_notification, :inner_bin, {:child_notification, :element, {:pad_removed, _pad}}}
      )

      Testing.Pipeline.execute_actions(pipeline, remove_child_pad: {:bin, Pad.ref(:input, 1)})

      assert_pipeline_notified(
        pipeline,
        :bin,
        {:child_notification, :inner_bin, {:pad_removed, Pad.ref(:input, _id)}}
      )

      assert_pipeline_notified(
        pipeline,
        :bin,
        {:child_notification, :inner_bin,
         {:child_notification, :element, {:pad_removed, Pad.ref(:input, _id)}}}
      )
    end

    @tag :skip
    test "triggered by pipeline removing bin's pad" do
      test "triggered by unlinking bin" do
        pipeline =
          Testing.Pipeline.start_link_supervised!(
            spec:
              child(:element, DynamicElement)
              |> via_out(Pad.ref(:output, 1))
              |> via_in(Pad.ref(:input, 1))
              |> child(:bin, NestedBin)
          )

        assert_pipeline_notified(pipeline, :element, :playing)
        assert_pipeline_notified(pipeline, :bin, :playing)
        assert_pipeline_notified(pipeline, :bin, {:child_notification, :inner_bin, :playing})

        assert_pipeline_notified(
          pipeline,
          :bin,
          {:child_notification, :inner_bin, {:child_notification, :element, :playing}}
        )

        Testing.Pipeline.execute_actions(pipeline, remove_child_pad: {:bin, Pad.ref(:input, 1)})

        assert_pipeline_notified(pipeline, :bin, {:pad_removed, Pad.ref(:input, 1)})

        refute_pipeline_notified(
          pipeline,
          :bin,
          {:child_notification, :inner_bin, {:pad_removed, _pad}}
        )

        refute_pipeline_notified(
          pipeline,
          :bin,
          {:child_notification, :inner_bin, {:child_notification, :element, {:pad_removed, _pad}}}
        )

        Testing.Pipeline.execute_actions(pipeline, remove_child_pad: {:bin, Pad.ref(:input, 1)})

        assert_pipeline_notified(
          pipeline,
          :bin,
          {:child_notification, :inner_bin, {:pad_removed, Pad.ref(:input, _id)}}
        )

        assert_pipeline_notified(
          pipeline,
          :bin,
          {:child_notification, :inner_bin,
           {:child_notification, :element, {:pad_removed, Pad.ref(:input, _id)}}}
        )
      end

    end
  end
end
