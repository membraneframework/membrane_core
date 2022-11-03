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
  def handle_init(_ctx, _opts) do
    children = [
      child(:center_filter, Filter),
      child(:sink, Testing.Sink)
    ]

    links = [
      get_child(:center_filter)
      |> get_child(:sink)
    ]

    spec = children ++ links

    {{:ok, spec: spec, playback: :playing}, %{}}
  end

  @impl true
  def handle_info({:create_path, spec}, _ctx, state) do
    {{:ok, spec: spec}, state}
  end

  @spec add_single_source(pid(), any(), any(), any()) :: any()
  def add_single_source(pid, source_name, group \\ nil, source \\ Testing.Source) do
    children = [
      child(source_name, source)
    ]

    links = [
      get_child(source_name)
      |> get_child(:center_filter)
    ]

    spec = children ++ links

    spec =
      if group do
        {spec, crash_group: {group, :temporary}}
      else
        spec
      end

    send(pid, {:create_path, spec})
  end

  @spec add_bin(pid(), atom(), atom(), any()) :: any()
  def add_bin(pid, bin_name, source_name, group \\ nil) do
    children = [child(source_name, Testing.Source), child(bin_name, TestBins.CrashTestBin)]

    links = [
      get_child(source_name) |> get_child(bin_name) |> get_child(:center_filter)
    ]

    spec = children ++ links

    spec =
      if group do
        {spec, crash_group: {group, :temporary}}
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
    children =
      [child(source_name, Testing.Source)] ++ (filters_names |> Enum.map(&child(&1, Filter)))

    children_names = [source_name | filters_names]

    links =
      Enum.chunk_every(children_names, 2, 1, [:center_filter])
      |> Enum.map(fn [first_elem, second_elem] ->
        get_child(first_elem) |> get_child(second_elem)
      end)

    spec = children ++ links

    spec =
      if group do
        {spec, crash_group: {group, :temporary}}
      else
        spec
      end

    send(pid, {:create_path, spec})
  end
end
