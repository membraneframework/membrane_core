defmodule Membrane.Support.PipelineHelpers do
  @moduledoc false

  alias Membrane.Testing
  require Membrane.Testing.Assertions

  @spec assert_data_flows_through(pid(), list(), :atom) :: :ok | no_return()
  def assert_data_flows_through(pipeline, buffers, receiving_element \\ :sink) do
    assert_playing(pipeline)
    :ok = Testing.Assertions.assert_start_of_stream(pipeline, ^receiving_element)
    :ok = assert_buffers_flow_through(pipeline, buffers, receiving_element)
    :ok = Testing.Assertions.assert_end_of_stream(pipeline, ^receiving_element)
  end

  @spec assert_playing(pid()) :: :ok
  def assert_playing(pipeline) do
    :ok = Testing.Pipeline.play(pipeline)
    Testing.Assertions.assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
    Testing.Assertions.assert_pipeline_playback_changed(pipeline, :prepared, :playing)
  end

  @spec assert_buffers_flow_through(pid(), list(), atom()) :: :ok
  def assert_buffers_flow_through(pipeline, buffers, receiving_element) do
    buffers
    |> Enum.each(fn b ->
      Testing.Assertions.assert_sink_buffer(pipeline, receiving_element, %Membrane.Buffer{
        payload: ^b
      })
    end)
  end

  @spec stop_pipeline(pid()) :: :ok
  def stop_pipeline(pipeline) do
    Membrane.Pipeline.stop_and_terminate(pipeline)
    Testing.Assertions.assert_pipeline_playback_changed(pipeline, :prepared, :stopped)

    receive do
      {:DOWN, _, _, _, _} ->
        :ok
    after
      100 ->
        {:error, :timeout}
    end
  end
end
