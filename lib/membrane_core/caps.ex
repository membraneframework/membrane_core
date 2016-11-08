defmodule Membrane.Caps do
  @type content_type :: String.t
  @type channels_type :: non_neg_integer
  @type sample_rate_type :: non_neg_integer
  @type frame_size_type :: 1 | 2 | 4
  @type endianness_type :: :le | :be

  @type t :: %Membrane.Caps{
    content: Membrane.Caps.content_type,
    channels: Membrane.Caps.channels_type
    frame_size: Membrane.Caps.frame_size_type
    endianness: Membrane.Caps.endianness_type
  }

  defstruct content: nil, channels: nil, sample_rate: nil, endianness: nil, frame_size: nil
end
