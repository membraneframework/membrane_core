defmodule Membrane.Element do
  @moduledoc """
  Module containing types and functions for operating on elements.

  For behaviours for elements check `Membrane.Source`, `Membrane.Filter`,
  `Membrane.Endpoint` and `Membrane.Sink`.

  ## Behaviours
  Element-specific behaviours are specified in modules:
  - `Membrane.Element.WithOutputPads` - behaviour common to sources,
  filters and endpoints
  - `Membrane.Element.WithInputPads` - behaviour common to sinks,
  filters and endpoints
  - Base modules (`Membrane.Source`, `Membrane.Filter`, `Membrane.Endpoint`,
  `Membrane.Sink`) - behaviours specific to each element type.

  ## Callbacks
  Modules listed above provide specifications of callbacks that define elements
  lifecycle. All of these callbacks have names with the `handle_` prefix.
  They are used to define reaction to certain events that happen during runtime,
  and indicate what actions framework should undertake as a result, besides
  executing element-specific code.

  For actions that can be returned by each callback, see `Membrane.Element.Action`
  module.
  """

  @typedoc """
  Defines options that can be received in `c:Membrane.Element.Base.handle_init/2`
  callback.
  """
  @type options :: struct | nil

  @typedoc """
  Type that defines an element name by which it is identified.
  """
  @type name :: tuple() | atom()

  @typedoc """
  Defines possible element types:
  - source, producing buffers
  - filter, processing buffers
  - endpoint, producing and consuming buffers
  - sink, consuming buffers
  """
  @type type :: :source | :filter | :endpoint | :sink

  @typedoc """
  Type of user-managed state of element.
  """
  @type state :: any()

  @doc """
  Checks whether module is an element.
  """
  @spec element?(module) :: boolean
  def element?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_element?)
  end

  defguard is_element_name?(arg) when is_atom(arg) or is_tuple(arg)
end
