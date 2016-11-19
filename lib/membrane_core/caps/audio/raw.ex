defmodule Membrane.Caps.Audio.Raw do
  @moduledoc """
  This module implements struct for caps representing raw audio stream with
  interleaved channels.
  """

  @type channels_type :: non_neg_integer
  @type sample_rate_type :: non_neg_integer
  @type format_type :: :s16le # TODO add more formats

  @type t :: %Membrane.Caps.Audio.Raw{
    channels: Membrane.Caps.Audio.Raw.channels_type,
    sample_rate: Membrane.Caps.Audio.Raw.sample_rate_type,
    format: Membrane.Caps.Audio.Raw.format_type
  }

  defstruct \
    channels: nil,
    sample_rate: nil,
    format: nil
end
