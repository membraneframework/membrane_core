defmodule Membrane.Pad do
  @type name_t         :: atom | String.t
  @type availability_t :: :always
  @type known_caps_t   :: :any | [Membrane.Caps.t]
  @type known_pads_t   :: %{required(name_t) => {availability_t, known_caps_t}}


end
