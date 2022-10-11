defmodule Membrane.Support.CapsTest.Sink do
  @moduledoc """
  Sink used in caps test.
  Sends info to pid given in init opts, about its own pid.
  Notifies parent on caps arrival.
  """

  use Membrane.Endpoint

  alias Membrane.Support.CapsTest

  def_input_pad :input,
    demand_unit: :buffers,
    caps: :any,
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(%__MODULE__{test_pid: test_pid}) do
    send(test_pid, {:sink_pid, self()})
    {:ok, %{}}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, state) do
    {{:ok, notify_parent: {:caps_received, caps}}, state}
  end
end
