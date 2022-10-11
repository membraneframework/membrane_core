defmodule Membrane.Support.CapsTest.Bin do
  @moduledoc """
  Bin used in caps test.
  Has caps spec for `:input` pad.
  Spawns `Membrane.Support.CapsTest.Sink` as its child.
  Forwards all notifications from children to parent.
  """

  use Membrane.Bin

  alias Membrane.Support.CapsTest

  @accepted_format CapsTest.Stream.FormatA
  @unaccepted_format CapsTest.Stream.FormatB

  def_input_pad :input,
    demand_unit: :buffers,
    caps: {CapsTest.Stream, format: @accepted_format},
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(%__MODULE__{test_pid: test_pid}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        bin_input()
        |> child(:sink, %CapsTest.Sink{test_pid: test_pid})
      ]
    }

    state = %{}

    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_child_notification(msg, _child, _ctx, state) do
    {{:ok, notify_parent: msg}, state}
  end

  @spec accepted_format() :: module()
  def accepted_format(), do: @accepted_format

  @spec unaccepted_format() :: module()
  def unaccepted_format(), do: @unaccepted_format
end
