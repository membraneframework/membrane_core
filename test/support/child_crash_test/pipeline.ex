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
    spec =
      child(:center_filter, Filter)
      |> child(:sink, Testing.Sink)

    {[spec: spec], %{}}
  end

  @impl true
  def handle_info({:create_path, spec}, _ctx, state) do
    {[spec: spec], state}
  end

  @spec add_single_source(pid(), any(), any(), any()) :: any()
  def add_single_source(pid, source_name, group \\ nil, source \\ Testing.Source) do
    spec = child(source_name, source) |> get_child(:center_filter)

    spec =
      if group do
        {spec, crash_group_mode: :temporary, group: group}
      else
        spec
      end

    send(pid, {:create_path, spec})
  end

  @spec add_bin(pid(), atom(), atom(), any()) :: any()
  def add_bin(pid, bin_name, source_name, group \\ nil) do
    spec =
      child(source_name, Testing.Source)
      |> child(bin_name, TestBins.CrashTestBin)
      |> get_child(:center_filter)

    spec =
      if group do
        {spec, crash_group_mode: :temporary, group: group}
      else
        spec
      end

    send(pid, {:create_path, spec})
  end

  @spec add_path(pid(), [atom()], atom(), any(), any()) :: any()
  def add_path(
        pid,
        filters_names,
        source_name,
        group,
        group_mode
      ) do
    children =
      [child(source_name, Testing.Source)] ++ (filters_names |> Enum.map(&child(&1, Filter)))

    children_names = [source_name | filters_names]

    links =
      children_names
      |> Enum.chunk_every(2, 1, [:center_filter])
      |> Enum.map(fn [first_child_name, second_child_name] ->
        get_child(first_child_name)
        |> get_child(second_child_name)
      end)

    spec = children ++ links

    spec =
      if group do
        {spec, crash_group_mode: group_mode, group: group}
      else
        spec
      end

    send(pid, {:create_path, spec})
  end
end
