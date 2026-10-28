defmodule Membrane.Support.DemandsTest.Helpers do
  @moduledoc false
  import ExUnit.Assertions
  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.Testing.Pipeline

  @settle_timeout 300

  @spec assert_sink_payloads(pid(), Membrane.Child.name(), Enumerable.t()) :: :ok
  def assert_sink_payloads(pipeline, sink, payloads) do
    Enum.each(payloads, fn payload ->
      assert_sink_buffer(pipeline, sink, buffer)
      assert buffer.payload == payload
    end)
  end

  @spec assert_notified_in_order(pid(), Membrane.Child.name(), [term()]) :: :ok
  def assert_notified_in_order(pipeline, child, expected_notifications) do
    Enum.each(expected_notifications, fn expected_notification ->
      assert_pipeline_notified(pipeline, child, notification)
      assert notification == expected_notification
    end)
  end

  @spec await_settled_production(pid(), Membrane.Child.name()) :: non_neg_integer()
  def await_settled_production(pipeline, source) do
    assert_pipeline_notified(pipeline, source, {:handle_demand, _size, produced})
    await_settled_production(pipeline, source, produced)
  end

  @spec await_settled_production(pid(), Membrane.Child.name(), non_neg_integer()) ::
          non_neg_integer()
  def await_settled_production(pipeline, source, produced) do
    receive do
      {Pipeline, ^pipeline,
       {:handle_child_notification, {{:handle_demand, _size, produced}, ^source}}} ->
        await_settled_production(pipeline, source, produced)
    after
      @settle_timeout -> produced
    end
  end

  @spec send_buffers(pid(), Membrane.Child.name(), Enumerable.t()) :: :ok
  def send_buffers(pipeline, source, payloads) do
    buffers = Enum.map(payloads, &%Buffer{payload: &1})
    Pipeline.notify_child(pipeline, source, buffer: {:output, buffers})
  end
end
