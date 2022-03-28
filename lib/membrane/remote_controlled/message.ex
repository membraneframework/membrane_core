defmodule Membrane.RemoteControlled.Message do
  @moduledoc """
  An abstract module aggregating all the messages that can be sent by the `RemoteControlled.Pipeline`.
  The available messages are:
  * `Membrane.RemoteControlled.Message.PlaybackState.t()`
  * `Membrane.RemoteControlled.Message.StartOfStream.t()`
  * `Membrane.RemoteControlled.Message.EndOfStream.t()`
  * `Membrane.RemoteControlled.Message.Notification.t()`
  * `Membrane.RemoteControlled.Message.Terminated.t()`
  """

  @type message_t ::
          __MODULE__.PlaybackState.t()
          | __MODULE__.StartOfStream.t()
          | __MODULE__.EndOfStream.t()
          | __MODULE__.Notification.t()
          | __MODULE__.Terminated.t()

  defmodule PlaybackState do
    @moduledoc """
    Message sent when the pipeline changes its playback state
    """
    @type t :: %__MODULE__{from: pid(), state: Membrane.PlaybackState.t()}

    @enforce_keys [:from, :state]
    defstruct @enforce_keys
  end

  defmodule StartOfStream do
    @moduledoc """
    Message sent when some element of the pipeline receives the start of stream event on some pad.
    """
    @type t :: %__MODULE__{
            from: pid(),
            element: Membrane.Element.name_t(),
            pad: Membrane.Pad.name_t()
          }

    @enforce_keys [:from, :element, :pad]
    defstruct @enforce_keys
  end

  defmodule EndOfStream do
    @moduledoc """
    Message sent when some element of the pipeline receives the start of stream event on some pad.
    """
    @type t :: %__MODULE__{
            from: pid(),
            element: Membrane.Element.name_t(),
            pad: Membrane.Pad.name_t()
          }

    @enforce_keys [:from, :element, :pad]
    defstruct @enforce_keys
  end

  defmodule Notification do
    @moduledoc """
    Message sent when the some element of the pipeline receives a notification.
    """
    @type t :: %__MODULE__{
            from: pid(),
            element: Membrane.Element.name_t(),
            data: Membrane.Notification.t()
          }

    @enforce_keys [:from, :element, :data]
    defstruct @enforce_keys
  end

  defmodule Terminated do
    @moduledoc """
    Message sent when the pipeline gracefully terminates.
    """
    @type t :: %__MODULE__{from: pid(), reason: :normal | :shutdown | {:shutdown, any()} | term()}

    @enforce_keys [:from, :reason]
    defstruct @enforce_keys
  end
end
