defmodule Membrane.Element.Core.CapsOverride do
  @moduledoc """
  Element capable of overriding caps of buffers flowing through it.

  Useful if you e.g. read file with raw data of known type, File source returns
  buffers with unknown caps and you want to convert these caps annotation into
  right format.
  """

  use Membrane.Element.Base.Filter
  alias Membrane.Element.Core.CapsOverrideOptions


  def_known_source_pads %{
    :source => {:always, :any}
  }

  def_known_sink_pads %{
    :sink => {:always, :any}
  }


  # Private API

  @doc false
  def handle_init(%CapsOverrideOptions{caps: caps}) do
    {:ok, %{
      caps: caps,
    }}
  end


  @doc false
  def handle_buffer(buffer, %{caps: caps} = state) do
    {:send, [%Membrane.Buffer{buffer | caps: caps}], state}
  end
end
