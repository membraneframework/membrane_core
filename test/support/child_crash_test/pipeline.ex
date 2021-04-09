defmodule Membrane.Support.ChildCrashTest.Pipeline do
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

  # @impl true
  # def handle_other({:DOWN, _, _, _, _} = msg, _ctx, state) do
  #   IO.inspect(msg, label: "%%%")
  #   {:ok, state}
  # end

  @spec add_single_source(pid(), any(), any()) :: any()
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
    children_names = children |> Enum.map(&(elem(&1, 0)))
    children_count = length(children)

    links =
      children_names
      |> Enum.with_index()
      |> Enum.map(fn {child, i} ->
        if i < children_count - 1, do: link(child) |> to(Enum.at(children_names, i + 1)),
      else: link(child) |> to(:center_filter)
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
