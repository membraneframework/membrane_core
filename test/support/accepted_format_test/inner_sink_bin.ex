defmodule Membrane.Support.AcceptedFormatTest.InnerSinkBin do
  @moduledoc """
  Bin used in stream format test.
  It has a :accepted_format defined for the `:input` pad.
  Spawns `Membrane.Support.AcceptedFormatTest.Sink` as its child.
  """

  use Membrane.Bin

  alias Membrane.Support.AcceptedFormatTest
  alias Membrane.Support.AcceptedFormatTest.StreamFormat
  alias Membrane.Support.AcceptedFormatTest.StreamFormat.{AcceptedByAll, AcceptedByInnerBins}

  def_input_pad :input,
    demand_unit: :buffers,
    accepted_format:
      %StreamFormat{format: format} when format in [AcceptedByAll, AcceptedByInnerBins],
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        bin_input()
        |> child(:sink, %AcceptedFormatTest.Sink{test_pid: test_pid})
      ]
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_child_notification(msg, _child, _ctx, state) do
    {{:ok, notify_parent: msg}, state}
  end
end
