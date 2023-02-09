defmodule Membrane.Child do
  @moduledoc """
  Module that keeps track of types used by both elements and bins
  """
  import Membrane.Element, only: [is_element_name?: 1]
  import Membrane.Bin, only: [is_bin_name?: 1]

  alias Membrane.{Bin, Element}
  @default_ref_options [group: [default: nil]]

  @type name :: Element.name() | Bin.name()
  @type group() :: any()
  @type ref :: {Membrane.Child, group(), name()} | name()

  @type options :: Element.options() | Bin.options()

  defguard is_child_name?(arg) when is_element_name?(arg) or is_bin_name?(arg)

  @type child_ref_options :: [group: group()]

  @doc """
  Returns a reference to a child.
  """
  @spec ref(name(), child_ref_options()) :: ref()
  def ref(name, options \\ []) do
    validate_name!(name)
    {:ok, options} = Bunch.Config.parse(options, @default_ref_options)
    validate_name!(options.group)

    if options.group != nil,
      do: {Membrane.Child, options.group, name},
      else: name
  end

  defp validate_name!(name) do
    if is_tuple(name) and elem(name, 0) == Membrane.Child do
      raise "Improper name: #{inspect(name)}. The name cannot match the reserved internal Membrane's pattern."
    end

    :ok
  end
end
