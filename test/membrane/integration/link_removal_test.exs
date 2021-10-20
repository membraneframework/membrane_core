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

  defp setup_pipeline(_ctx) do
    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        elements: [
          source: %Testing.Source{output: @buffers},
          test_bin: %TestBins.DynamicBin{
            children: [
              filter1: TestDynamicPadFilter,
              filter2: TestDynamicPadFilter,
              filter3: TestDynamicPadFilter
            ],
            links: [
              link(:filter1) |> to(:filter2) |> to(:filter3)
            ],
            receiver: self()
          },
          sink: Testing.Sink
        ]
      })

    assert_data_flows_through(pipeline, @buffers)

    [pipeline: pipeline]
  end

  describe "removing links" do
    setup :setup_pipeline

    test "can remove a bin input", %{pipeline: pipeline} do
      Testing.Pipeline.execute_actions(pipeline, remove_link: [link(:source) |> to(:test_bin)])

      assert_pad_removed(pipeline, :test_bin, Pad.ref(:input, _id))
      refute_pad_removed(pipeline, :test_bin, Pad.ref(:output, _id))

      Testing.Assertions.assert_end_of_stream(pipeline, :test_bin, Pad.ref(:input, _id))

      stop_pipeline(pipeline)
    end

    test "can remove a bin output", %{pipeline: pipeline} do
      Testing.Pipeline.execute_actions(pipeline, remove_link: [link(:test_bin) |> to(:sink)])

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
  end
end
