defmodule Membrane.Support.AcceptedFormatTest.Source do
  @moduledoc """
  Source used in stream format test.
  Sends stream format passed in opts, after entering the `:playing` playback state.
  """

  use Membrane.Source

  alias Membrane.Support.AcceptedFormatTest.StreamFormat

  def_output_pad :output,
    demand_unit: :buffers,
    accepted_format: StreamFormat,
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid],
              stream_format: [type: :any]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid, stream_format: stream_format}) do
    send(test_pid, {:my_pid, __MODULE__, self()})
    {:ok, %{test_pid: test_pid, stream_format: stream_format}}
  end

  @impl true
  def handle_playing(_ctx, %{stream_format: stream_format} = state) do
    {{:ok, stream_format: {:output, stream_format}}, state}
  end
end
