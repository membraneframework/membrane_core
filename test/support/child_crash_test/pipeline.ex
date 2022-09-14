defmodule Membrane.Support.ChildCrashTest.Pipeline do
  @moduledoc """
  Pipeline used in child crash test.
  Allows adding specs by handling message `:create_path`.
  """

  use Membrane.Pipeline

  alias Membrane.Support.Bin.TestBins
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
      structure: children ++ links
    }

    {{:ok, spec: spec, playback: :playing}, %{}}
  end

  @impl true
  def handle_info({:create_path, spec}, _ctx, state) do
    {{:ok, spec: spec}, state}
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
      structure: children ++ links
    }

    spec =
      if group do
        %{spec | crash_group: :temporary, children_group_id: group}
      else
        spec
      end

    send(pid, {:create_path, spec})
  end

  @spec add_bin(pid(), atom(), atom(), any()) :: any()
  def add_bin(pid, bin_name, source_name, group \\ nil) do
    children = [{source_name, Testing.Source}, {bin_name, TestBins.CrashTestBin}]

    links = [
      link(source_name) |> to(bin_name) |> to(:center_filter)
    ]

    spec = %Membrane.ParentSpec{
      structure: children ++ links
    }

    spec =
      if group do
        %{spec | crash_group: :temporary, children_group_id: group}
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
      structure: children ++ links
    }

    spec =
      if group do
        %{spec | crash_group: :temporary, children_group_id: group}
      else
        spec
      end

    send(pid, {:create_path, spec})
  end
end
