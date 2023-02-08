defmodule Membrane.Integration.PipelineTest do
  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions

  alias Membrane.Testing

  defmodule Endpoint do
    use Membrane.Endpoint

    def_output_pad :output,
      demand_mode: :auto,
      caps: :any,
      demand_unit: :buffers,
      availability: :on_request

    def_input_pad :input,
      demand_mode: :auto,
      caps: :any,
      demand_unit: :buffers,
      availability: :on_request

    @impl true
    def handle_init(_opts) do
      notification = {:endpoint_pid, self()}
      {{:ok, notify: notification}, %{}}
    end
  end

  defmodule Bin do
    use Membrane.Bin

    alias Membrane.Integration.PipelineTest.Endpoint

    def_output_pad :output, demand_mode: :auto, caps: :any, demand_unit: :buffers

    @impl true
    def handle_init(_opts) do
      spec = %Membrane.ParentSpec{
        children: [endpoint: Endpoint],
        links: [
          link(:endpoint) |> to_bin_output(:output)
        ]
      }

      notification = {:bin_pid, self()}

      {{:ok, notify: notification, spec: spec}, %{}}
    end

    @impl true
    def handle_notification(notification, child, _ctx, state) do
      msg = {:child_notification, child, notification}
      {{:ok, notify: msg}, state}
    end
  end

  @tag :debug
  test "Membrane.Pipeline.kill/2" do
    children = [
      bin: Bin,
      element: Endpoint
    ]

    links = Membrane.ParentSpec.link_linear(children)
    {:ok, pipeline} = Testing.Pipeline.start(links: links)

    assert_pipeline_notified(pipeline, :bin, {:bin_pid, bin_pid})
    assert_pipeline_notified(pipeline, :element, {:endpoint_pid, endpoint_pid})

    assert_pipeline_notified(
      pipeline,
      :bin,
      {:child_notification, :endpoint, {:endpoint_pid, nested_endpoint_pid}}
    )

    monitors =
      for pid <- [pipeline, bin_pid, endpoint_pid, nested_endpoint_pid] do
        Process.monitor(pid)
      end

    assert :ok == Membrane.Pipeline.kill(pipeline, blocking?: true)

    for ref <- monitors do
      assert_receive {:DOWN, ^ref, _process, _pid, _reason}
    end
  end
end
