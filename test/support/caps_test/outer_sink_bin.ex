defmodule Membrane.Support.StreamFormatTest.OuterSinkBin do
  @moduledoc """
  Bin used in stream format test.
  It has a :accepted_format defined for the `:input` pad.
  Spawns `Membrane.Support.StreamFormatTest.InnerSinkBin` as its child.
  """

  use Membrane.Bin

  alias Membrane.Support.StreamFormatTest
  alias Membrane.Support.StreamFormatTest.StreamFormat
  alias Membrane.Support.StreamFormatTest.StreamFormat.{AcceptedByAll, AcceptedByOuterBins}

  def_input_pad :input,
    demand_unit: :buffers,
    accepted_format:
      any_of(%StreamFormat{format: AcceptedByAll}, %StreamFormat{format: AcceptedByOuterBins}),
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        bin_input()
        |> child(:sink, %StreamFormatTest.InnerSinkBin{test_pid: test_pid})
      ]
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_child_notification(msg, _child, _ctx, state) do
    {{:ok, notify_parent: msg}, state}
  end
end
