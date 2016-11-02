defmodule Membrane.Const do
  @sample_rate              48000   # Hz
  @frame_size               2       # bytes
  @channels                 2

  def sample_rate,              do: @sample_rate
  def frame_size,               do: @frame_size
  def channels,                 do: @channels
end
