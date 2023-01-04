defmodule Membrane.Support.AcceptedFormatTest.Source do
  @moduledoc """
  Source used in accepted format tests.
  Sends stream format passed in opts, after entering the `:playing` playback.
  """

  use Membrane.Source

  alias Membrane.Support.AcceptedFormatTest.StreamFormat

  def_output_pad :output,
    accepted_format: StreamFormat,
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid],
              stream_format: [type: :any]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid, stream_format: stream_format}) do
    send(test_pid, {:my_pid, __MODULE__, self()})
    {[], %{test_pid: test_pid, stream_format: stream_format}}
  end

  @impl true
  def handle_playing(_ctx, %{stream_format: stream_format} = state) do
    {[stream_format: {:output, stream_format}], state}
  end
end
