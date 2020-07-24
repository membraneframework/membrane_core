defmodule Membrane.Notification do
  @moduledoc """
  A notification is a message sent from `Membrane.Element` to a parent
  via action `t:Membrane.Element.Action.notify_t/0` returned from any callback.

  A notification can be handled in parent with
  `c:Membrane.Parent.handle_notification/4` callback.

  The example of a notification is tuple `{:end_of_stream, pad_ref}` that, by default,
  is sent when handling `Membrane.Event.EndOfStream` event
  """

  @type t :: any
end
