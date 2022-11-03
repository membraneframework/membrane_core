defmodule Membrane.Support.Element.DynamicFilter do
  @moduledoc """
  This is a mock filter with dynamic inputs for use in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Bunch
  use Membrane.Filter

  def_input_pad :input, accepted_format: _any, availability: :on_request, demand_mode: :auto
  def_output_pad :output, accepted_format: _any, availability: :on_request, demand_mode: :auto

  @impl true
  def handle_init(_ctx, _options) do
    {:ok, %{}}
  end

  @impl true
  def handle_pad_added(pad, _ctx, state) do
    {{:ok, notify_parent: {:pad_added, pad}}, state |> Map.put(:last_pad_addded, pad)}
  end

  @impl true
  def handle_pad_removed(pad, _ctx, state) do
    {{:ok, notify_parent: {:pad_removed, pad}}, state |> Map.put(:last_pad_removed, pad)}
  end

  @impl true
  def handle_event(ref, event, _ctx, state) do
    {{:ok, forward: event}, state |> Map.put(:last_event, {ref, event})}
  end
end
