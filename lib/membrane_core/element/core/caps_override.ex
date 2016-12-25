defmodule Membrane.Element.Core.CapsOverride do
  @moduledoc """
  This element can be used to override caps of buffers.

  Useful if you e.g. read file with raw data of known type, File source returns
  buffers with unknown caps and you want to convert these caps annotation into
  right format.
  """

  use Membrane.Element.Base.Filter
  alias Membrane.Element.Core.CapsOverrideOptions


  # Private API

  @doc false
  def potential_sink_pads(), do: %{
    :sink => {:always, :any}
  }


  @doc false
  def potential_source_pads(), do: %{
    :source => {:always, :any}
  }


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
