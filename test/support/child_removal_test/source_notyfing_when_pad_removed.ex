defmodule Membrane.Support.ChildRemovalTest.SourceNotyfingWhenPadRemoved do
  @moduledoc false
  use Membrane.Source

  def_output_pad :first, caps: :any, demand_mode: :auto, availability: :on_request
  def_output_pad :second, caps: :any, demand_mode: :auto, availability: :on_request
  def_output_pad :third, caps: :any, demand_mode: :auto, availability: :on_request
  def_output_pad :fourth, caps: :any, demand_mode: :auto, availability: :on_request
  def_output_pad :fifth, caps: :any, demand_mode: :auto, availability: :on_request

  @impl true
  def handle_init(_ctx, _opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_pad_removed(pad, _ctx, state) do
    {{:ok, notify_parent: {:pad_removed, pad}}, state}
  end
end
