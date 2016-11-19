defmodule Membrane.Element.Core.CapsOverrideOptions do
  defstruct \
    caps: nil

  @type t :: %Membrane.Element.Core.CapsOverrideOptions{
    caps: map | nil
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


  # Private API

  @doc false
  def handle_init(%CapsOverrideOptions{caps: caps}) do
    {:ok, %{
      caps: caps,
    }}
  end


  @doc false
  def handle_buffer(buffer, %{caps: caps} = state) do
    {:send_buffer, %Membrane.Buffer{buffer | caps: caps}, state}
  end
end
