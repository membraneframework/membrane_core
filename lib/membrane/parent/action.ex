defmodule Membrane.Parent.Action do
  @moduledoc """
  Common types' definitions for bin and pipeline.
  """

  alias Membrane.{Child, Notification, ParentSpec}

  @typedoc """
  Action that sends a message to a child identified by name.
  """
  @type forward_action_t :: {:forward, {Child.name_t(), Notification.t()}}

  @typedoc """
  Action that instantiates children and links them according to `Membrane.ParentSpec`.

  Children's playback state is changed to the current parent state.
  `c:Membrane.Parent.handle_spec_started/3` callback is executed once it happens.
  """
  @type spec_action_t :: {:spec, ParentSpec.t()}

  @typedoc """
  Action that stops, unlinks and removes specified child/children from their parent.
  """
  @type remove_child_action_t ::
          {:remove_child, Child.name_t() | [Child.name_t()]}

  @typedoc """
  Action that sets `Logger` metadata for the parent and all its descendants.

  Uses `Logger.metadata/1` underneath.
  """
  @type log_metadata_action_t :: {:log_metadata, Keyword.t()}

  @typedoc """
  Type describing actions that can be returned from parent callbacks.

  Returning actions is a way of pipeline/bin interaction with its children and
  other parts of framework.
  """
  @type t :: forward_action_t | spec_action_t | remove_child_action_t
end
