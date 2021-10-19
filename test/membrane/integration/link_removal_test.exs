defmodule Membrane.Core.LinkRemovalTest do
  use ExUnit.Case, async: true

  import Membrane.ParentSpec
  import Membrane.Support.PipelineHelpers

  alias Membrane.Pad
  alias Membrane.Support.Bin.TestBins
  alias Membrane.Support.Bin.TestBins.TestDynamicPadFilter
  alias Membrane.Testing

  require Membrane.Pad

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

      assert_receive {Membrane.Testing.Pipeline, ^pipeline, {:execute_actions, _links}}

      assert_receive {Membrane.Testing.Pipeline, ^pipeline,
                      {:handle_notification,
                       {{:handle_pad_removed, Pad.ref(:input, _id)}, :test_bin}}}

      stop_pipeline(pipeline)
    end

    test "can remove a bin output", %{pipeline: pipeline} do
      Testing.Pipeline.execute_actions(pipeline, remove_link: [link(:test_bin) |> to(:sink)])

      assert_receive {Membrane.Testing.Pipeline, ^pipeline, {:execute_actions, _links}}

      assert_receive {Membrane.Testing.Pipeline, ^pipeline,
                      {:handle_notification,
                       {{:handle_pad_removed, Pad.ref(:output, _id)}, :test_bin}}}

      stop_pipeline(pipeline)
    end

    test "can remove links between elements", %{pipeline: pipeline} do
      Testing.Pipeline.message_child(
        pipeline,
        :test_bin,
        {:remove_link, [link(:filter1) |> to(:filter2)]}
      )

      assert_receive {Membrane.Testing.Pipeline, ^pipeline,
                      {:handle_notification, {:link_removed, :test_bin}}}

      assert_receive {Membrane.Testing.Pipeline, ^pipeline,
                      {:handle_notification,
                       {{:handle_notification, :filter1,
                         {:handle_pad_removed, Pad.ref(:output, _ref)}}, :test_bin}}}

      assert_receive {Membrane.Testing.Pipeline, ^pipeline,
                      {:handle_notification,
                       {{:handle_notification, :filter2,
                         {:handle_pad_removed, Pad.ref(:input, _ref)}}, :test_bin}}}

      stop_pipeline(pipeline)
    end
  end
end
