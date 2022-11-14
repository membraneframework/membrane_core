defmodule Membrane.Element do
  @moduledoc """
  Module containing types and functions for operating on elements.

  For behaviours for elements chceck `Membrane.Source`, `Membrane.Filter`,
  `Membrane.Endpoint` and `Membrane.Sink`.
  """

  @typedoc """
  Defines options that can be received in `c:Membrane.Element.Base.handle_init/2`
  callback.
  """
  @type options_t :: struct | nil

  @typedoc """
  Type that defines an element name by which it is identified.
  """
  @type name_t :: tuple() | atom()

  @typedoc """
  Defines possible element types:
  - source, producing buffers
  - filter, processing buffers
  - endpoint, producing and consuming buffers
  - sink, consuming buffers
  """
  @type type_t :: :source | :filter | :endpoint | :sink

  @typedoc """
  Type of user-managed state of element.
  """
  @type state_t :: any()

  @doc """
  Checks whether module is an element.
  """
  @spec element?(module) :: boolean
  def element?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_element?)
  end

  defguard is_element_name?(arg) when is_atom(arg) or is_tuple(arg)
end
