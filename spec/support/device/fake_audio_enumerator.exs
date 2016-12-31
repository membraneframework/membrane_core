defmodule Membrane.Support.Device.FakeAudioEnumerator do
  @moduledoc """
  This is minimal sample audio enumerator for using in specs.

  Modify with caution as many specs may depend on its shape.
  """

  use Membrane.Device.AudioEnumerator
  alias Membrane.Device.AudioDevice


  @capture [
    %AudioDevice{
      direction: :capture,
      driver: :spec,
      name: "ABC",
      id: "abc",
    },
    %AudioDevice{
      direction: :capture,
      driver: :spec,
      name: "DEF",
      id: "def",
    },
  ]

  @playback [
    %AudioDevice{
      direction: :playback,
      driver: :spec,
      name: "GHI",
      id: "ghi",
    },
    %AudioDevice{
      direction: :playback,
      driver: :spec,
      name: "IJK",
      id: "ijk",
    },
  ]


  def list(:capture) do
    {:ok, @capture}
  end


  def list(:playback) do
    {:ok, @playback}
  end


  def list(:all) do
    {:ok, @capture ++ @playback}
  end
end
