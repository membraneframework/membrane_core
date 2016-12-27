defmodule Membrane.Device.AudioDevice do
  @moduledoc """
  Structure representing a single audio device.

  It is meant to provide uniform and extendable interface for storing lists
  of devices, e.g. returned by enumerators that are supposed to determine
  what hardware is available in the system.

  It contains the following fields and all of them should be present:

  * `name` - human readable device name,
  * `id` - unique identifier of the device, that is persistent accross reboots,
  * `driver` - atom identyfing driver used for accessing the device, e.g. `:wasapi`,
    `:alsa`,
  * `direction` - an be either `:capture` or `:playback`.
  """

  @type name_t      :: String.t
  @type id_t        :: String.t
  @type driver_t    :: atom
  @type direction_t :: :capture | :playback

  @type t :: %Membrane.Device.AudioDevice{
    name: name_t,
    id: id_t,
    driver: driver_t,
    direction: direction_t
  }

  defstruct \
    name: nil,
    id: nil,
    driver: driver,
    direction: direction
end
