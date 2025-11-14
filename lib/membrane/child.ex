defmodule Membrane.Child do
  @moduledoc """
  Module that keeps track of types used by both elements and bins
  """
  import Membrane.Element, only: [is_element_name?: 1]
  import Membrane.Bin, only: [is_bin_name?: 1]

  alias Membrane.{Bin, Element}

  @typedoc "Any type except for `nil`"
  @type non_nil :: any()

  @typedoc "Name of the child"
  @type name :: Element.name() | Bin.name()

  @typedoc """
  Specifies the children group name. 

  Can be any type except for `nil`
  """
  @type group() :: non_nil()

  @typedoc "Options of the child"
  @type options :: Element.options() | Bin.options()

  defguard is_child_name?(arg) when is_element_name?(arg) or is_bin_name?(arg)
end
