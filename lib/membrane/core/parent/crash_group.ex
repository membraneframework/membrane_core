defmodule Membrane.Core.Parent.CrashGroup do
  @moduledoc false

  # A module representing crash group:
  #   * name - name that identifies the group
  #   * type - responsible for restart policy of members of groups
  #   * members - list of members of group
  #   * reason - reason of the crash

  use Bunch.Access

  @type name() :: any()

  @type t :: %__MODULE__{
          name: name(),
          mode: :temporary,
          members: [Membrane.Child.name()],
          detonating?: boolean(),
          crash_initiator: Membrane.Child.name(),
          reason: any()
        }

  @enforce_keys [:name, :mode]
  defstruct @enforce_keys ++
              [members: [], detonating?: false, crash_initiator: nil, reason: :normal]
end
