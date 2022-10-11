defmodule Membrane.Support.CapsTest.Source do
  @moduledoc """
  Source used in caps test.
  Sends caps received in message from parent, after entering the `:playing` playback state.
  """

  use Membrane.Source

  def_output_pad :output, demand_unit: :buffers, caps: :any, availability: :always, mode: :push

  @impl true
  def handle_init(_opts) do
    {:ok, %{}}
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
  def handle_parent_notification({:send_caps, caps}, _ctx, _state) do
    {:ok, %{caps: caps}}
  end
end
