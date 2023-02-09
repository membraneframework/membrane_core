defmodule Membrane.Support.ChildRemovalTest.SourceNotyfingWhenPadRemoved do
  @moduledoc false
  use Membrane.Source

  def_output_pad :first, accepted_format: _any, flow_control: :push, availability: :on_request
  def_output_pad :second, accepted_format: _any, flow_control: :push, availability: :on_request
  def_output_pad :third, accepted_format: _any, flow_control: :push, availability: :on_request
  def_output_pad :fourth, accepted_format: _any, flow_control: :push, availability: :on_request
  def_output_pad :fifth, accepted_format: _any, flow_control: :push, availability: :on_request

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{}}
  end

  @impl true
  def handle_pad_removed(pad, _ctx, state) do
    {[notify_parent: {:pad_removed, pad}], state}
  end
end
