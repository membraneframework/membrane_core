defmodule Membrane.Core.Parent.ChildLifeController.CrashGroupHandler do
  @moduledoc """
  A module responsible for managing crash groups inside the state of pipeline.
  """

  alias Membrane.ParentSpec
  alias Membrane.Core.Pipeline
  alias Membrane.Core.Parent.CrashGroup

  # for now only Pipeline.State has crash_groups field
  @spec add_crash_group(ParentSpec.crash_group_spec_t(), [pid()], Pipeline.State.t()) ::
          {:ok, Pipeline.State.t()}
  def add_crash_group(group_spec, children_pids, state) do
    {group_name, mode} = group_spec
    crash_group = %CrashGroup{name: group_name, mode: mode, members: children_pids}

    {:ok, %{state | crash_groups: [crash_group | state.crash_groups]}}
  end

  @spec remove_crash_group(CrashGroup.name_t(), Pipeline.State.t()) :: {:ok, Pipeline.State.t()}
  def remove_crash_group(group_name, state) do
    crash_groups = state.crash_groups |> Enum.reject(&(&1.name == group_name))

    {:ok, %{state | crash_groups: crash_groups}}
  end
end
