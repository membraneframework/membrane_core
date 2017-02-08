defmodule Membrane.Device.AudioEndpoint do
  @moduledoc """
  Structure representing a single audio endpoint.

  It is meant to provide uniform and extendable interface for storing lists
  of endpoints, e.g. returned by enumerators that are supposed to determine
  what hardware is available in the system, hiding underlying differences
  between audio drivers.

  It contains the following fields and all of them should be present:

  * `name` - human readable device name,
  * `interface` - human readable interface name of this endpoint or nil if
     it is not known (not all drivers will expose this information),
  * `id` - unique identifier of the device, that is persistent accross reboots,
  * `driver` - atom identyfing driver used for accessing the device, e.g. `:wasapi`,
    `:alsa`,
  * `direction` - an be either `:capture` or `:playback`,
  * `state` - endpoint state, can be one of `:active`, `:disabled`, `:notpresent`
    or `:unplugged`.
  """

  @type id_t        :: String.t
  @type name_t      :: String.t
  @type interface_t :: String.t | nil
  @type driver_t    :: atom
  @type direction_t :: :capture | :playback
  @type state_t     :: :active | :disabled | :notpresent | :unplugged

  @type t :: %Membrane.Device.AudioEndpoint{
    name: name_t,
    id: id_t,
    driver: driver_t,
    direction: direction_t,
    interface: interface_t,
    state: state_t,
  }

  defstruct \
    name: nil,
    id: nil,
    driver: nil,
    direction: nil,
    interface: nil,
    state: nil
end
