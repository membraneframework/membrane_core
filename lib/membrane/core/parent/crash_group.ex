defmodule Membrane.Core.Parent.CrashGroup do
  @moduledoc false

  # A module representing crash group:
  #   * name - name that identifies the group
  #   * type - responsible for restart policy of members of groups
  #   * members - list of members of group

  use Bunch.Access

  @type name_t() :: any()

  @type t :: %__MODULE__{
          name: name_t(),
          mode: :temporary,
          members: [Membrane.Child.name_t()],
          alive_members_pids: [pid()],
          triggered?: boolean(),
          crash_initiator: Membrane.Child.name_t()
        }

  @enforce_keys [:name, :mode]
  defstruct @enforce_keys ++
              [members: [], alive_members_pids: [], triggered?: false, crash_initiator: nil]
end
