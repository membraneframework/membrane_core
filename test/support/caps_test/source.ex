defmodule Membrane.Support.CapsTest.Source do
  @moduledoc """
  Source used in caps test.
  Sends caps received in message from parent, after entering the `:playing` playback state.
  """

  use Membrane.Source

  alias Membrane.Support.CapsTest.Stream

  def_output_pad :output,
    demand_unit: :buffers,
    caps: Stream,
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(%__MODULE__{test_pid: test_pid}) do
    send(test_pid, {:my_pid, __MODULE__, self()})
    {:ok, %{test_pid: test_pid}}
  end

  @impl true
  def handle_playing(_ctx, %{caps: caps} = state) do
    {{:ok, caps: {:output, caps}}, state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_parent_notification({:send_caps, caps}, %{playback: :playing}, state) do
    {{:ok, caps: {:output, caps}}, state}
  end

  @impl true
  def handle_parent_notification({:send_caps, caps}, _ctx, state) do
    {:ok, Map.put(state, :caps, caps)}
  end
end
