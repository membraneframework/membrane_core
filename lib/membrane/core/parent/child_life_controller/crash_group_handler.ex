defmodule Membrane.Core.Parent.ChildLifeController.CrashGroupHandler do
  alias Membrane.{ParentSpec, Child}
  alias Membrane.Core.Pipeline

  # for now only Pipeline.State has crash_groups field
  @spec add_crash_group(ParentSpec.crash_group_spec_t(), [Child.name_t()], Pipeline.State.t()) ::
          {:ok | {:error, any}, Pipeline.State.state_t()}
  def add_crash_group(group_spec, children_pids, state) do
    {group_id, type} = group_spec
    crash_group = {group_id, type, children_pids}

    {:ok, %{state | crash_groups: [crash_group | state.crash_groups]}}
  end
end
