defmodule Membrane.ChildNotification do
  @moduledoc """
  A child notification is a message sent from `Membrane.Element` or `Membrane.Bin` to a parent
  via action `t:Membrane.Element.Action.notify_parent_t` or `t:Membrane.Bin.Action.notify_parent_t`
  returned from any callback.

  A notification can be handled in parent with
  `c:Membrane.Parent.handle_child_notification/4` callback.
  """

  @type t :: any
end

defmodule Membrane.ParentNotification do
  @moduledoc """
  A parent notification is a message sent from `Membrane.Parent` or `Membrane.Bin` to a child
  via action `t:Membrane.Pipeline.Action.notify_parent_t` or `t:Membrane.Bin.Action.notify_child_t`
  returned from any callback.

  A notification can be handled in child with `c:Membrane.Element.Base.handle_parent_notification/3` or
  `c:Membrane.Bin.handle_parent_notification/3` callback.
  """

  @type t :: any
end
