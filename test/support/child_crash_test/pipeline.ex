defmodule Membrane.Support.ChildCrashTest.Pipeline do
  @moduledoc """
  Pipeline used in child crash test.
  Allows adding specs by handling message `:create_path`.
  """

  use Membrane.Pipeline

  alias Membrane.Support.ChildCrashTest.Filter
  alias Membrane.Testing

  @spec crash_child(pid()) :: any()
  def crash_child(pid) do
    send(pid, :crash)
  end

  @impl true
  def handle_init(_opts) do
    children = [
      center_filter: Filter,
      sink: Testing.Sink
    ]

    links = [
      link(:center_filter)
      |> to(:sink)
    ]

    spec = %Membrane.ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_other({:create_path, spec}, _ctx, state) do
    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_other({:handle_crash_group_called, _group_name}, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_crash_group_down(group_name, _ctx, state) do
    send(self(), {:handle_crash_group_called, group_name})
    {:ok, state}
  end

  @spec add_single_source(pid(), any(), any(), any()) :: any()
  def add_single_source(pid, source_name, group \\ nil, source \\ Testing.Source) do
    children = [
      {source_name, source}
    ]

    links = [
      link(source_name)
      |> to(:center_filter)
    ]

    spec = %Membrane.ParentSpec{
      children: children,
      links: links
    }

    spec =
      if group do
        %{spec | crash_group: group}
      else
        spec
      end

    send(pid, {:create_path, spec})
  end

  @spec add_path(pid(), [atom()], atom(), any()) :: any()
  def add_path(
        pid,
        filters_names,
        source_name,
        group \\ nil
      ) do
    children = [{source_name, Testing.Source}] ++ (filters_names |> Enum.map(&{&1, Filter}))
    children_names = children |> Enum.map(&elem(&1, 0))

    links =
      Enum.chunk_every(children_names, 2, 1, [:center_filter])
      |> Enum.map(fn [first_elem, second_elem] ->
        link(first_elem) |> to(second_elem)
      end)

    spec = %Membrane.ParentSpec{
      children: children,
      links: links
    }

    spec =
      if group do
        %{spec | crash_group: group}
      else
        spec
      end

    send(pid, {:create_path, spec})
  end
end
