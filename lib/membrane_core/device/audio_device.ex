defmodule Membrane.Device.AudioEndpoint do
  @moduledoc """
  Structure representing a single audio device.

  It is meant to provide uniform and extendable interface for storing lists
  of devices, e.g. returned by enumerators that are supposed to determine
  what hardware is available in the system.

  It contains the following fields and all of them should be present:

  * `name` - human readable device name,
  * `interface` - human readable interface name of this endpoint or nil if
     it is not known (not all drivers will expose this information),
  * `id` - unique identifier of the device, that is persistent accross reboots,
  * `driver` - atom identyfing driver used for accessing the device, e.g. `:wasapi`,
    `:alsa`,
  * `direction` - an be either `:capture` or `:playback`.
  """

  @type id_t        :: String.t
  @type name_t      :: String.t
  @type interface_t :: String.t | nil
  @type driver_t    :: atom
  @type direction_t :: :capture | :playback

  @type t :: %Membrane.Device.AudioEndpoint{
    name: name_t,
    id: id_t,
    driver: driver_t,
    direction: direction_t,
    interface: interface_t,
  }

  defstruct \
    name: nil,
    id: nil,
    driver: nil,
    direction: nil,
    interface: nil
end
