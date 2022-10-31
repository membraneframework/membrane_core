defmodule Membrane.Support.AcceptedFormatTest.InnerSourceBin do
  @moduledoc """
  Bin used in stream format test.
  It has a :accepted_format defined for the `:output` pad.
  Spawns `Membrane.Support.AcceptedFormatTest.Source` as its child.
  """

  use Membrane.Bin

  alias Membrane.Support.AcceptedFormatTest
  alias Membrane.Support.AcceptedFormatTest.StreamFormat
  alias Membrane.Support.AcceptedFormatTest.StreamFormat.{AcceptedByAll, AcceptedByInnerBins}

  def_output_pad :output,
    demand_unit: :buffers,
    accepted_format:
      %StreamFormat{format: format} when format in [AcceptedByAll, AcceptedByInnerBins]

  def_options test_pid: [type: :pid],
              stream_format: [type: :any]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid, stream_format: stream_format}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        child(:source, %AcceptedFormatTest.Source{
          test_pid: test_pid,
          stream_format: stream_format
        })
        |> bin_output()
      ]
    }

    {{:ok, spec: spec}, %{}}
  end
end
