defmodule Membrane.Child do
  @moduledoc """
  Module that keeps track of types used by both elements and bins
  """
  alias Membrane.{Bin, Element}

  @type name_t :: Element.name_t() | Bin.name_t()

  @type options_t :: Element.options_t() | Bin.options_t()

  @type children_group_id_t() :: any()
end
