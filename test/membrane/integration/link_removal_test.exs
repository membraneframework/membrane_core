defmodule Membrane.Core.LinkRemovalTest do
  use ExUnit.Case, async: true

  import Membrane.ParentSpec
  import Membrane.Support.PipelineHelpers

  alias Membrane.Pad
  alias Membrane.Support.Bin.TestBins
  alias Membrane.Support.Bin.TestBins.TestDynamicPadFilter
  alias Membrane.Testing

  require Membrane.Pad
  require Membrane.Testing.Assertions

  @buffers ['a', 'b', 'c']

  ExUnit.Case.register_attribute(__MODULE__, :sink_module)

  defp setup_pipeline(ctx) do
    test_pid = self()
    sink_module = ctx.registered.sink_module || Testing.DynamicSink

    sink_pad = if sink_module == Testing.DynamicSink, do: Pad.ref(:input, 1), else: :input

    links = [
      link(:source)
      |> via_out(Pad.ref(:output, 1))
      |> to(:test_bin)
      |> via_in(sink_pad)
      |> to(:sink)
    ]

    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        crash_group: {:test, :temporary},
        test_process: test_pid,
        elements: [
          source: %Testing.DynamicSource{output: @buffers},
          test_bin: %TestBins.DynamicBin{
            children: [
              filter1: TestDynamicPadFilter,
              filter2: TestDynamicPadFilter,
              filter3: TestDynamicPadFilter
            ],
            links: [
              link(:filter1) |> to(:filter2) |> to(:filter3)
            ],
            receiver: test_pid
          },
          sink: sink_module
        ],
        links: links
      })

    assert_data_flows_through(pipeline, @buffers, :sink, sink_pad)

    [pipeline: pipeline, sink_pad: sink_pad]
  end

  describe "removing links" do
    setup :setup_pipeline

    test "can remove a bin input", %{pipeline: pipeline} do
      Testing.Pipeline.execute_actions(pipeline,
        remove_link: [link(:source) |> via_out(Pad.ref(:output, 1)) |> to(:test_bin)]
      )

      assert_pad_removed(pipeline, :test_bin, Pad.ref(:input, _id))
      refute_pad_removed(pipeline, :test_bin, Pad.ref(:output, _id))

      Testing.Assertions.assert_end_of_stream(pipeline, :test_bin, Pad.ref(:input, _id))

      stop_pipeline(pipeline)
    end

    test "can remove a bin output", %{pipeline: pipeline, sink_pad: sink_pad} do
      Testing.Pipeline.execute_actions(pipeline,
        remove_link: [link(:test_bin) |> via_in(sink_pad) |> to(:sink)]
      )

      assert_pad_removed(pipeline, :test_bin, Pad.ref(:output, _id))
      refute_pad_removed(pipeline, :test_bin, Pad.ref(:input, _id))

      Testing.Assertions.assert_end_of_stream(pipeline, :test_bin, Pad.ref(:input, _id))

      stop_pipeline(pipeline)
    end

    test "can remove links between elements", %{pipeline: pipeline} do
      Testing.Pipeline.message_child(
        pipeline,
        :test_bin,
        {:remove_link, [link(:filter1) |> to(:filter2)]}
      )

      assert_nested_pad_removed(pipeline, :test_bin, :filter1, Pad.ref(:output, _ref))
      assert_nested_pad_removed(pipeline, :test_bin, :filter2, Pad.ref(:input, _ref))

      Testing.Assertions.assert_end_of_stream(pipeline, :test_bin, Pad.ref(:input, _id))

      refute_pad_removed(pipeline, :test_bin, Pad.ref(:output, _id))
      refute_pad_removed(pipeline, :test_bin, Pad.ref(:input, _id))

      stop_pipeline(pipeline)
    end

    @sink_module Testing.Sink
    test "raises when unlink a static pad", %{pipeline: pipeline} do
      ExUnit.CaptureLog.capture_log(fn ->
        Testing.Pipeline.execute_actions(pipeline,
          remove_link: [link(:test_bin) |> via_in(:input) |> to(:sink)]
        )
      end)

      assert_receive {_pipeline, _pid, {:handle_crash_group_down, :test}}
    end
  end
end
