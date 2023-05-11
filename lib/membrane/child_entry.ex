defmodule Membrane.ChildEntry do
  @moduledoc """
  Struct describing child entry of a parent.

  The public fields are:
  - `name` - child name
  - `module` - child module
  - `options` - options passed to the child
  - `component_type` - either `:element` or `:bin`

  Other fields in the struct ARE NOT PART OF THE PUBLIC API and should not be
  accessed or relied on.
  """
  use Bunch.Access

  @typedoc @moduledoc
  @type t :: %__MODULE__{
          name: Membrane.Child.name(),
          module: module,
          options: struct | nil,
          component_type: :element | :bin,
          pid: pid,
          clock: Membrane.Clock.t(),
          sync: Membrane.Sync.t(),
          terminating?: boolean(),
          group: Membrane.Child.group()
        }

  defstruct [
    :name,
    :module,
    :options,
    :component_type,
    :pid,
    :clock,
    :sync,
    :spec_ref,
    :group,
    initialized?: false,
    ready?: false,
    terminating?: false
  ]
end
