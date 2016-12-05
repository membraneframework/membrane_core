defmodule Membrane.Caps.Audio.Raw do
  @moduledoc """
  This module implements struct for caps representing raw audio stream with
  interleaved channels.
  """

  @type channels_t :: non_neg_integer
  @type sample_rate_t :: non_neg_integer
  @type format_t :: :s16le # TODO add more formats

  @type t :: %Membrane.Caps.Audio.Raw{
    channels: channels_t,
    sample_rate: sample_rate_t,
    format: format_t
  }

  defstruct \
    channels: nil,
    sample_rate: nil,
    format: nil
end
