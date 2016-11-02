defmodule Membrane.Caps do
  @type content_type :: String.t
  @type t :: %Membrane.Caps{content: Membrane.Caps.content_type}

  defstruct content: nil


  def to_gstreamer(%Membrane.Caps{content: "audio/x-raw"}) do
    # FIXME do not use hardcoded format
    "audio/x-raw,rate=#{Membrane.Const.sample_rate},format=S16LE,channels=#{Membrane.Const.channels}"
  end
end
