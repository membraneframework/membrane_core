defmodule Membrane.Support.StreamFormatTest.OuterSourceBin do
  @moduledoc """
  Bin used in stream format test.
  It has a accepted_format defined for the `:output` pad.
  Spawns `Membrane.Support.StreamFormatTest.InnerSourceBin` as its child.
  """

  use Membrane.Bin

  alias Membrane.Support.StreamFormatTest
  alias Membrane.Support.StreamFormatTest.StreamFormat
  alias Membrane.Support.StreamFormatTest.StreamFormat.{AcceptedByAll, AcceptedByOuterBins}

  def_output_pad :output,
    demand_unit: :buffers,
    accepted_format:
      %StreamFormat{format: format} when format in [AcceptedByAll, AcceptedByOuterBins]

  def_options test_pid: [type: :pid],
              stream_format: [type: :any]

  @impl true
  def handle_init(_ctx, %__MODULE__{test_pid: test_pid, stream_format: stream_format}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        child(:inner_source_bin, %StreamFormatTest.InnerSourceBin{
          test_pid: test_pid,
          stream_format: stream_format
        })
        |> bin_output()
      ]
    }

    {{:ok, spec: spec}, %{}}
  end
end
