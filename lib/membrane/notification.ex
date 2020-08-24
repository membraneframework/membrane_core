defmodule Membrane.Notification do
  @moduledoc """
  A notification is a message sent from `Membrane.Element` to a parent
  via action `t:Membrane.Element.Action.notify_t/0` returned from any callback.

  A notification can be handled in parent with
  `c:Membrane.Parent.handle_notification/4` callback.
  """

  @type t :: any
end
