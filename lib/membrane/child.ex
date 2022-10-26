defmodule Membrane.Child do
  @moduledoc """
  Module that keeps track of types used by both elements and bins
  """
  import Membrane.Element, only: [is_element_name?: 1]
  import Membrane.Bin, only: [is_bin_name?: 1]

  alias Membrane.{Bin, Element}

  @type name_t :: Element.name_t() | Bin.name_t()

  @type options_t :: Element.options_t() | Bin.options_t()

  defguard is_child_name?(arg) when is_element_name?(arg) or is_bin_name?(arg)
end
