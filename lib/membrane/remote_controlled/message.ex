defmodule Membrane.RemoteControlled.Message do
  @moduledoc """
  A module defining the structure of the message which can be received by the pipeline.
  This structure wraps the specific message type instance (i.e. Message.PlaybackState message) inside the `body` field
  and provides an additional `:from` field with the pid of the message sender.
  """
  @type t :: %__MODULE__{
          from: pid(),
          body:
            Membrane.RemoteControlled.Message.PlaybackState.t()
            | Membrane.RemoteControlled.Message.StartOfStream.t()
            | Membrane.RemoteControlled.Message.EndOfStream.t()
            | Membrane.RemoteControlled.Message.Notification.t()
            | Membrane.RemoteControlled.Message.Terminated.t()
        }

  @enforce_keys [:from, :body]
  defstruct @enforce_keys

  defmodule PlaybackState do
    @moduledoc """
    Message sent when the pipeline changes its playback state
    """
    @type t :: %__MODULE__{state: Membrane.PlaybackState.t()}

    @enforce_keys [:state]
    defstruct @enforce_keys
  end

  defmodule StartOfStream do
    @moduledoc """
    Message sent when some element of the pipeline receives the start of stream event on some pad.
    """
    @type t :: %__MODULE__{element: Membrane.Element.name_t(), pad: Membrane.Pad.name_t()}

    @enforce_keys [:element, :pad]
    defstruct @enforce_keys
  end

  defmodule EndOfStream do
    @moduledoc """
    Message sent when some element of the pipeline receives the start of stream event on some pad.
    """
    @type t :: %__MODULE__{element: Membrane.Element.name_t(), pad: Membrane.Pad.name_t()}

    @enforce_keys [:element, :pad]
    defstruct @enforce_keys
  end

  defmodule Notification do
    @moduledoc """
    Message sent when the some element of the pipeline receives a notification.
    """
    @type t :: %__MODULE__{element: Membrane.Element.name_t(), data: Membrane.Notification.t()}

    @enforce_keys [:element, :data]
    defstruct @enforce_keys
  end

  defmodule Terminated do
    @moduledoc """
    Message sent when the pipeline is terminated.
    """
    @type t :: %__MODULE__{reason: :normal | :shutdown | {:shutdown, any()} | term()}

    @enforce_keys [:reason]
    defstruct @enforce_keys
  end
end
