defmodule Membrane.Core.Parent.ChildrenModel do
  @moduledoc false

  alias Membrane.{Child, ChildEntry, UnknownChildError}
  alias Membrane.Core.Parent

  @type children :: %{Child.name() => ChildEntry.t()}

  @spec assert_child_exists!(Parent.state(), Child.name()) :: :ok
  def assert_child_exists!(state, child) do
    _data = get_child_data!(state, child)
    :ok
  end

  @spec get_child_data!(Parent.state(), Child.name()) :: ChildEntry.t()
  def get_child_data!(%{children: children}, child) do
    case children do
      %{^child => data} -> data
      _children -> raise UnknownChildError, name: child, children: children
    end
  end

  @spec update_children!(Parent.state(), [Child.name()], (ChildEntry.t() -> ChildEntry.t())) ::
          Parent.state()
  def update_children!(%{children: children} = state, children_names, mapper) do
    children =
      Enum.reduce(children_names, children, fn name, children ->
        case children do
          %{^name => data} -> %{children | name => mapper.(data)}
          _children -> raise UnknownChildError, name: name, children: children
        end
      end)

    %{state | children: children}
  end

  @spec update_children(Parent.state(), (ChildEntry.t() -> ChildEntry.t())) :: Parent.state()
  def update_children(%{children: children} = state, mapper) do
    children = Map.new(children, fn {name, entry} -> {name, mapper.(entry)} end)
    %{state | children: children}
  end

  @spec all?(Parent.state(), (ChildEntry.t() -> as_boolean(term))) :: boolean()
  def all?(state, predicate) do
    state.children
    |> Enum.all?(fn {_k, v} -> predicate.(v) end)
  end
end
