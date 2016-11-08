defmodule Membrane.Element.Core.CapsOverrideOptions do
  defstruct caps: nil

  @type t :: %Membrane.Element.Core.CapsOverrideOptions{
    caps: %Membrane.Caps{}
  }
end


defmodule Membrane.Element.Core.CapsOverride do
  @moduledoc """
  This element can be used to override caps of buffers.

  Useful if you e.g. read file with raw data of known type, File source returns
  buffers with caps set to application/octet-stream and you want to convert
  this caps annotation into right format.
  """

  use Membrane.Element.Base.Filter
  alias Membrane.Element.Core.CapsOverrideOptions


  def handle_prepare(%CapsOverrideOptions{caps: caps}) do
    {:ok, %{caps: caps}}
  end


  def handle_buffer(_caps, data, %{caps: caps} = state) do
    {:send_buffer, {caps, data}, state}
  end
end
