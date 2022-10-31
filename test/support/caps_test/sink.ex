defmodule Membrane.Support.CapsTest.Sink do
  @moduledoc """
  Sink used in caps test.
  Sends a message with its own pid to the process specified in the options.
  Notifies parent on caps arrival.
  """

  use Membrane.Endpoint

  alias Membrane.Support.CapsTest.Stream

  def_input_pad :input,
    demand_unit: :buffers,
    accepted_format: Stream,
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid}) do
    send(test_pid, {:my_pid, __MODULE__, self()})
    {:ok, %{test_pid: test_pid}}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, state) do
    {{:ok, notify_parent: {:caps_received, caps}}, state}
  end
end
