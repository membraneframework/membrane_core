defmodule Membrane.Support.AcceptedFormatTest.RestrictiveSource do
  @moduledoc """
  Source used in accepted format tests.
  Sends stream format passed in opts, after entering the `:playing` playback.
  """

  use Membrane.Source

  alias Membrane.Support.AcceptedFormatTest.StreamFormat

  def_output_pad :output,
    accepted_format: %StreamFormat{format: StreamFormat.AcceptedByAll},
    availability: :always,
    flow_control: :push

  def_options test_pid: [type: :pid],
              stream_format: [type: :any]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid, stream_format: stream_format}) do
    {[], %{test_pid: test_pid, stream_format: stream_format}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    send(state.test_pid, {:my_pid, __MODULE__, self()})
    {[], state}
  end

  @impl true
  def handle_info(:send_stream_format, _ctx, state) do
    {[stream_format: {:output, state.stream_format}], state}
  end
end
