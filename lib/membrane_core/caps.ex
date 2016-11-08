defmodule Membrane.Caps do
  @type content_type :: String.t
  @type channels_type :: non_neg_integer

  @type t :: %Membrane.Caps{
    content: Membrane.Caps.content_type,
    channels: Membrane.Caps.channels_type
  }

  defstruct content: nil, channels: nil
end
