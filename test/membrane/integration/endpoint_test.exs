defmodule Membrane.Core.EndpointTest do
  use ExUnit.Case, async: true

  import Membrane.ParentSpec
  import Membrane.Testing.Assertions

  alias Membrane.Support.Bin.TestBins.TestFilter
  alias Membrane.Testing

  require Membrane.Core.Message

  describe "Starting and transmitting buffers" do
    test "with one endpoint and filter" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            endpoint: %Testing.Endpoint{output: buffers},
            filter: TestFilter
          ],
          links: [
            link(:endpoint) |> to(:filter),
            link(:filter) |> to(:endpoint)
          ]
        })

      assert_data_flows_through(pipeline, buffers, :endpoint)
    end

    test "with one endpoint and many filters in between" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            endpoint: %Testing.Endpoint{output: buffers},
            filter1: TestFilter,
            filter2: TestFilter,
            filter3: TestFilter
          ],
          links: [
            link(:endpoint) |> to(:filter1),
            link(:filter1) |> to(:filter2),
            link(:filter2) |> to(:filter3),
            link(:filter3) |> to(:endpoint)
          ]
        })

      assert_data_flows_through(pipeline, buffers, :endpoint)
    end
  end

  defp assert_data_flows_through(pipeline, buffers, receiving_element) do
    Testing.Pipeline.execute_actions(pipeline, playback: :playing)

    assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)

    assert_start_of_stream(pipeline, ^receiving_element)

    buffers
    |> Enum.each(fn b ->
      assert_sink_buffer(pipeline, receiving_element, %Membrane.Buffer{payload: ^b})
    end)

    assert_end_of_stream(pipeline, ^receiving_element)
    Testing.Pipeline.terminate(pipeline, blocking?: true)
  end
end
