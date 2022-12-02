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
  @type ref_t :: {:__membrane_children_group_member__, group_t(), name_t()} | name_t()

  @type options_t :: Element.options_t() | Bin.options_t()

  defguard is_child_name?(arg) when is_element_name?(arg) or is_bin_name?(arg)

  @type child_ref_options_t :: [group: group_t()]

  @doc """
  Returns a reference to a child.
  """
  @spec ref(name_t(), child_ref_options_t()) :: ref_t()
  def ref(name, options \\ []) do
    validate_name!(name)
    {:ok, options} = Bunch.Config.parse(options, @default_ref_options)
    validate_name!(options.group)

    if options.group != nil,
      do: {:__membrane_children_group_member__, options.group, name},
      else: name
  end

  defp validate_name!(name) do
    if is_tuple(name) and
         elem(name, 0) |> Atom.to_string() |> String.starts_with?("__membrane") do
      raise "Improper name: #{inspect(name)}. The name cannot match the reserved internal Membrane's pattern."
    end

    :ok
  end
end
