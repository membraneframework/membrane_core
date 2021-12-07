defmodule Membrane.Support.PipelineHelpers do
  @moduledoc false

  alias Membrane.Child
  alias Membrane.Pad
  alias Membrane.Testing
  require Membrane.Testing.Assertions

  @spec assert_data_flows_through(pid(), list(), atom(), Pad.ref_t()) :: :ok | no_return()
  def assert_data_flows_through(
        pipeline,
        buffers,
        receiving_element \\ :sink,
        receiving_pad \\ :input
      ) do
    assert_playing(pipeline)
    :ok = Testing.Assertions.assert_start_of_stream(pipeline, ^receiving_element, ^receiving_pad)
    :ok = assert_buffers_flow_through(pipeline, buffers, receiving_element)
    :ok = Testing.Assertions.assert_end_of_stream(pipeline, ^receiving_element, ^receiving_pad)
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

  @spec assert_pad_removed(pid(), Child.name_t(), Pad.ref_t()) :: Macro.t()
  defmacro assert_pad_removed(pipeline, element, pad) do
    quote do
      import ExUnit.Assertions

      assert_receive(
        {Membrane.Testing.Pipeline, ^unquote(pipeline),
         {:handle_notification, {{:handle_pad_removed, unquote(pad)}, unquote(element)}}}
      )
    end
  end

  @spec refute_pad_removed(pid(), Child.name_t(), Pad.ref_t()) :: Macro.t()
  defmacro refute_pad_removed(pipeline, element, pad) do
    quote do
      import ExUnit.Assertions

      refute_receive(
        {Membrane.Testing.Pipeline, ^unquote(pipeline),
         {:handle_notification, {{:handle_pad_removed, unquote(pad)}, unquote(element)}}}
      )
    end
  end

  @spec assert_nested_pad_removed(pid(), Child.name_t(), Child.name_t(), Pad.ref_t()) :: Macro.t()
  defmacro assert_nested_pad_removed(pipeline, element, nested_element, pad) do
    quote do
      import ExUnit.Assertions

      assert_receive(
        {Membrane.Testing.Pipeline, ^unquote(pipeline),
         {:handle_notification,
          {{:handle_notification, unquote(nested_element), {:handle_pad_removed, unquote(pad)}},
           unquote(element)}}}
      )
    end
  end
end
