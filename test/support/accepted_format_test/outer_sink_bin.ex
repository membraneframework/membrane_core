defmodule Membrane.Support.AcceptedFormatTest.OuterSinkBin do
  @moduledoc """
  Bin used in accepted format tests.
  It has a :accepted_format defined for the `:input` pad.
  Spawns `Membrane.Support.AcceptedFormatTest.InnerSinkBin` as its child.
  """

  use Membrane.Bin

  alias Membrane.Support.AcceptedFormatTest
  alias Membrane.Support.AcceptedFormatTest.StreamFormat
  alias Membrane.Support.AcceptedFormatTest.StreamFormat.{AcceptedByAll, AcceptedByOuterBins}

  def_input_pad :input,
    accepted_format:
      any_of(%StreamFormat{format: AcceptedByAll}, %StreamFormat{format: AcceptedByOuterBins}),
    availability: :always

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid}) do
    spec =
      bin_input()
      |> child(:sink, %AcceptedFormatTest.InnerSinkBin{test_pid: test_pid})

    {[spec: spec], %{}}
  end

  @impl true
  def handle_child_notification(msg, _child, _ctx, state) do
    {[notify_parent: msg], state}
  end
end
