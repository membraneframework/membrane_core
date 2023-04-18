defmodule Membrane.Child do
  @moduledoc """
  Module that keeps track of types used by both elements and bins
  """
  import Membrane.Element, only: [is_element_name?: 1]
  import Membrane.Bin, only: [is_bin_name?: 1]

  alias Membrane.{Bin, Element}

  @type name :: Element.name() | Bin.name()
  @type group() :: any()
  @type ref :: {Membrane.Child, group(), name()} | name()

  @type options :: Element.options() | Bin.options()

  defguard is_child_name?(arg) when is_element_name?(arg) or is_bin_name?(arg)

  @type child_ref_options :: [group: group()]

  @doc """
  Returns a reference to a child.
  """
  defmacro ref(name) do
    quote do
      unquote(name)
    end
  end

  defmacro ref(name, group: group) do
    quote do
      {
        unquote(__MODULE__),
        unquote(group),
        unquote(name)
      }
    end
  end

  @doc """
  Returns a child name from a child reference.
  """
  def name_by_ref(ref(name, group: _group)), do: name
  def name_by_ref(ref(name)), do: name
end
