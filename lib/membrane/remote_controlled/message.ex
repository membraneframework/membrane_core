defmodule Membrane.RemoteControlled.Message do
  @moduledoc false

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
    @type t :: %__MODULE__{from: pid(), element: Membrane.Element.name_t(), pad: Membrane.Pad.name_t()}

    @enforce_keys [:from, :element, :pad]
    defstruct @enforce_keys
  end

  defmodule EndOfStream do
    @moduledoc """
    Message sent when some element of the pipeline receives the start of stream event on some pad.
    """
    @type t :: %__MODULE__{from: pid(), element: Membrane.Element.name_t(), pad: Membrane.Pad.name_t()}

    @enforce_keys [:from, :element, :pad]
    defstruct @enforce_keys
  end

  defmodule Notification do
    @moduledoc """
    Message sent when the some element of the pipeline receives a notification.
    """
    @type t :: %__MODULE__{from: pid(), element: Membrane.Element.name_t(), data: Membrane.Notification.t()}

    @enforce_keys [:from, :element, :data]
    defstruct @enforce_keys
  end

  defmodule Terminated do
    @moduledoc """
    Message sent when the pipeline is terminated.
    """
    @type t :: %__MODULE__{from: pid(), reason: :normal | :shutdown | {:shutdown, any()} | term()}

    @enforce_keys [:from, :reason]
    defstruct @enforce_keys
  end
end
