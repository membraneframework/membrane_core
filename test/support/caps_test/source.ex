defmodule Membrane.Support.CapsTest.Source do
  @moduledoc """
  Source used in caps test.
  Sends caps received in message from parent, after entering the `:playing` playback state.
  """

  use Membrane.Source

  alias Membrane.Support.CapsTest.Stream

  def_output_pad :output,
    demand_unit: :buffers,
    accepted_format: Stream,
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid],
              caps: [type: :any]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid, caps: caps}) do
    send(test_pid, {:my_pid, __MODULE__, self()})
    {:ok, %{test_pid: test_pid, caps: caps}}
  end

  @impl true
  def handle_playing(_ctx, %{caps: caps} = state) do
    {{:ok, caps: {:output, caps}}, state}
  end
end
