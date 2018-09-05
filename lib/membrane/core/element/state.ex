defmodule Membrane.Core.Element.State do
  @moduledoc false
  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Log, tags: :core
  alias Membrane.{Core, Element}
  alias Core.Element.{PadModel, PlaybackBuffer}
  alias Element.Pad
  alias Bunch.Type
  use Bunch
  alias __MODULE__, as: ThisModule
  alias Membrane.Core.{Playback, Playbackable}
  require Pad

  @type stateful_t(value) :: Type.stateful_t(value, t)
  @type stateful_try_t :: Type.stateful_try_t(t)
  @type stateful_try_t(value) :: Type.stateful_try_t(value, t)

  @type t :: %__MODULE__{
          module: module,
          type: Element.type_t(),
          name: Element.name_t(),
          internal_state: Element.state_t() | nil,
          pads: %{optional(Element.Pad.name_t()) => PadModel.pads_t()} | nil,
          message_bus: pid | nil,
          controlling_pid: pid | nil,
          playback: Playback.t(),
          playback_buffer: PlaybackBuffer.t()
        }

  defstruct [
    :module,
    :type,
    :name,
    :internal_state,
    :pads,
    :message_bus,
    :controlling_pid,
    :playback,
    :playback_buffer
  ]

  defimpl Playbackable, for: __MODULE__ do
    use Playbackable.Default
    def get_controlling_pid(%ThisModule{controlling_pid: pid}), do: pid
  end

  @doc """
  Initializes new state.
  """
  @spec new(module, Element.name_t()) :: t
  def new(module, name) do
    %__MODULE__{
      module: module,
      type: apply(module, :membrane_element_type, []),
      name: name,
      internal_state: nil,
      pads: nil,
      message_bus: nil,
      controlling_pid: nil,
      playback: %Playback{},
      playback_buffer: PlaybackBuffer.new()
    }
  end
end
