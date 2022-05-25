defmodule Membrane.Core.Element.State do
  @moduledoc false

  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Bunch.Access

  alias Membrane.{Clock, Element, Pad, Sync}
  alias Membrane.Core.{Playback, Timer}
  alias Membrane.Core.Child.{PadModel, PadSpecHandler}
  alias Membrane.Core.Element.PlaybackBuffer

  require Membrane.Pad

  @type t :: %__MODULE__{
          module: module,
          type: Element.type_t(),
          name: Element.name_t(),
          internal_state: Element.state_t() | nil,
          pads_info: PadModel.pads_info_t() | nil,
          pads_data: PadModel.pads_data_t() | nil,
          parent_pid: pid,
          playback: Playback.t(),
          playback_buffer: PlaybackBuffer.t(),
          supplying_demand?: boolean(),
          delayed_demands: MapSet.t({Pad.ref_t(), :supply | :redemand}),
          synchronization: %{
            timers: %{Timer.id_t() => Timer.t()},
            parent_clock: Clock.t(),
            latency: non_neg_integer(),
            stream_sync: Sync.t(),
            clock: Clock.t() | nil
          }
        }

  defstruct [
    :module,
    :type,
    :name,
    :internal_state,
    :pads_info,
    :pads_data,
    :parent_pid,
    :playback,
    :playback_buffer,
    :supplying_demand?,
    :delayed_demands,
    :synchronization,
    :demand_size
  ]

  @doc """
  Initializes new state.
  """
  @spec new(%{
          module: module,
          name: Element.name_t(),
          parent_clock: Clock.t(),
          sync: Sync.t(),
          parent: pid
        }) :: t
  def new(options) do
    %__MODULE__{
      module: options.module,
      type: options.module.membrane_element_type(),
      name: options.name,
      internal_state: nil,
      parent_pid: options.parent,
      playback: %Playback{},
      playback_buffer: PlaybackBuffer.new(),
      supplying_demand?: false,
      delayed_demands: MapSet.new(),
      synchronization: %{
        parent_clock: options.parent_clock,
        timers: %{},
        clock: nil,
        stream_sync: options.sync,
        latency: 0
      }
    }
    |> PadSpecHandler.init_pads()
  end
end
