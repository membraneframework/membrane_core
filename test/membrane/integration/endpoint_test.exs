defmodule Membrane.Core.EndpointTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Support.Bin.TestBins.TestFilter
  alias Membrane.Testing

  require Membrane.Core.Message

  describe "Starting and transmitting buffers" do
    test "with one endpoint and filter" do
      buffers = ['a', 'b', 'c']

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec: [
            child(:endpoint, %Testing.Endpoint{output: buffers}) |> child(:filter, TestFilter),
            get_child(:filter) |> get_child(:endpoint)
          ]
        )

      assert_data_flows_through(pipeline, buffers, :endpoint)
    end

    test "with one endpoint and many filters in between" do
      buffers = ['a', 'b', 'c']

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            [
              child(:endpoint, %Testing.Endpoint{output: buffers}),
              child(:filter1, TestFilter),
              child(:filter2, TestFilter),
              child(:filter3, TestFilter)
            ] ++
              [
                get_child(:endpoint) |> get_child(:filter1),
                get_child(:filter1) |> get_child(:filter2),
                get_child(:filter2) |> get_child(:filter3),
                get_child(:filter3) |> get_child(:endpoint)
              ]
        )

      assert_data_flows_through(pipeline, buffers, :endpoint)
    end
  end

  defp assert_data_flows_through(pipeline, buffers, receiving_element) do
    assert_start_of_stream(pipeline, ^receiving_element)

    buffers
    |> Enum.each(fn b ->
      assert_sink_buffer(pipeline, receiving_element, %Membrane.Buffer{payload: ^b})
    end)

    assert_end_of_stream(pipeline, ^receiving_element)
  end
end
