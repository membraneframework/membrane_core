defmodule Membrane.Test.DelayedDemandsLoopTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Debug
  alias Membrane.Testing

  defmodule Source do
    use Membrane.Source

    defmodule StreamFormat do
      defstruct []
    end

    @sleep_time 5

    def_output_pad :output,
      accepted_format: _any,
      availability: :on_request,
      flow_control: :manual

    @impl true
    def handle_demand(_pad, _size, :buffers, %{pads: pads}, state) do
      Process.sleep(@sleep_time)

      stream_format_actions =
        Enum.flat_map(pads, fn
          {pad_ref, %{start_of_stream?: false}} -> [stream_format: {pad_ref, %StreamFormat{}}]
          _pad_entry -> []
        end)

      buffer = %Buffer{payload: "a"}

      buffer_and_redemand_actions =
        Map.keys(pads)
        |> Enum.flat_map(&[buffer: {&1, buffer}, redemand: &1])

      {stream_format_actions ++ buffer_and_redemand_actions, state}
    end

    @impl true
    def handle_parent_notification(:request, _ctx, state) do
      {[notify_parent: :response], state}
    end
  end

  describe "delayed demands loop pauses from time to time, when source has" do
    test "1 pad", do: do_test(1)
    test "2 pads", do: do_test(2)
    test "10 pads", do: do_test(10)
  end

  defp do_test(sinks_number) do
    auto_demand_size = 20

    spec =
      Stream.repeatedly(fn ->
        get_child(:source)
        |> via_in(:input, auto_demand_size: auto_demand_size)
        |> child(Debug.Sink)
      end)
      |> Stream.take(sinks_number)
      |> Enum.concat([child(:source, Source)])

    pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

    Process.sleep(1_000)

    for _i <- 1..(auto_demand_size + 5) do
      Testing.Pipeline.notify_child(pipeline, :source, :request)
      assert_pipeline_notified(pipeline, :source, :response)
    end

    Testing.Pipeline.terminate(pipeline)
  end
end
