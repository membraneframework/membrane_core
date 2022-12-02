defmodule Membrane.Child do
  @moduledoc """
  Module that keeps track of types used by both elements and bins
  """
  import Membrane.Element, only: [is_element_name?: 1]
  import Membrane.Bin, only: [is_bin_name?: 1]

  alias Membrane.{Bin, Element}
  @default_ref_options [group: [default: nil]]

  @type name_t :: Element.name_t() | Bin.name_t()
  @type group_t() :: any()
  @opaque ref_t :: {:__membrane_children_group_member__, group_t(), name_t()} | name_t()

  @type options_t :: Element.options_t() | Bin.options_t()

  defguard is_child_name?(arg) when is_element_name?(arg) or is_bin_name?(arg)

  @type child_ref_options_t :: [group: group_t()]

  @doc """
  Returns a reference to a child.
  """
  @spec ref(name_t(), child_ref_options_t()) :: ref_t()
  def ref(name, options \\ []) do
    validate_child_name!(name)
    {:ok, options} = Bunch.Config.parse(options, @default_ref_options)

    if options.group != nil,
      do: {:__membrane_children_group_member__, options.group, name},
      else: name
  end

  @spec validate_child_name!(Membrane.Child.name_t()) :: no_return() | :ok
  defp validate_child_name!(child_name) do
    if Kernel.match?({:__membrane_children_group_member__, _, _}, child_name) or
         Kernel.match?({:__membrane_just_child_name__, _}, child_name) do
      raise "Improper child name: #{inspect(child_name)}. The child's name cannot match the reserved internal Membrane's pattern.
      If you attempt to refer to a child being a member of a children group with the `get_child` function, use the `:group` option."
    end

    :ok
  end
end
