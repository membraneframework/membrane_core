defmodule Membrane.Core.Element.State do
  @moduledoc false
  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Log, tags: :core
  alias Membrane.{Core, Element}
  alias Core.Element.PlaybackBuffer
  alias Element.Pad
  alias Element.Base.Mixin.CommonBehaviour
  use Membrane.Helper
  alias __MODULE__, as: ThisModule
  alias Membrane.Core.{Playback, Playbackable}
  require Pad

  @type t :: %__MODULE__{
          internal_state: CommonBehaviour.internal_state_t() | nil,
          module: module,
          type: Element.type_t(),
          name: Element.name_t(),
          playback: Playback.t(),
          pads: %{optional(Element.Pad.name_t()) => pid},
          message_bus: pid | nil,
          playback_buffer: PlaybackBuffer.t(),
          controlling_pid: pid | nil
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
      type: module.membrane_element_type(),
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
