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
    case __CALLER__.context do
      :match -> ref_in_a_match(name)
      _not_match -> ref_outside_a_match(name)
    end
  end

  defmacro ref(name, options) do
    case __CALLER__.context do
      :match ->
        Macro.expand(options, __CALLER__)
        |> Access.fetch(:group)
        |> case do
          {:ok, group_ast} -> ref_in_a_match(name, group_ast)
          :error -> raise "Improper options. The options must be in form of [group: group]."
        end

      _not_match ->
        ref_outside_a_match(name, options)
    end
  end

  defp ref_in_a_match(name) do
    quote do
      unquote(name)
    end
  end

  defp ref_in_a_match(name, group) do
    quote do
      {
        unquote(__MODULE__),
        unquote(group),
        unquote(name)
      }
    end
  end

  defp ref_outside_a_match(name) do
    quote generated: true do
      case unquote(name) do
        {unquote(__MODULE__), _group, _child} ->
          raise "Improper name: #{inspect(unquote(name))}. The name cannot match the reserved internal Membrane's pattern."

        name ->
          name
      end
    end
  end

  defp ref_outside_a_match(name, options) do
    quote generated: true do
      cond do
        match?({unquote(__MODULE__), _group, _child}, unquote(name)) ->
          raise "Improper name: #{inspect(unquote(name))}. The name cannot match the reserved internal Membrane's pattern."

        not match?([group: _group], unquote(options)) ->
          raise "Improper options: #{inspect(unquote(options))}. The options must be in form of [group: group]."

        true ->
          [group: group] = unquote(options)
          {unquote(__MODULE__), group, unquote(name)}
      end
    end
  end

  @doc """
  Returns a name of a child from its reference.
  """
  @spec name_by_ref(ref()) :: name()
  def name_by_ref(ref(name, group: _group)), do: name
  def name_by_ref(ref(name)), do: name
end
