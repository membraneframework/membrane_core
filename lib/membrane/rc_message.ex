defmodule Membrane.RCMessage do
  @moduledoc """
  An abstract module aggregating all the messages that can be sent by the `RCPipeline`.

  Check `t:t/0` for available messages.
  """

  @typedoc """
  The type describing all possible `Membrane.RCMessage`s.
  """
  @type t ::
          __MODULE__.Playing.t()
          | __MODULE__.StartOfStream.t()
          | __MODULE__.EndOfStream.t()
          | __MODULE__.Notification.t()
          | __MODULE__.Terminated.t()

  defmodule Playing do
    @moduledoc """
    Message sent when the pipeline starts playing
    """

    @typedoc @moduledoc
    @type t :: %__MODULE__{from: pid()}

    @enforce_keys [:from]
    defstruct @enforce_keys
  end

  defmodule StartOfStream do
    @moduledoc """
    Message sent when some element of the pipeline receives the start of stream event on some pad.
    """

    @typedoc @moduledoc
    @type t :: %__MODULE__{
            from: pid(),
            element: Membrane.Element.name(),
            pad: Membrane.Pad.name()
          }

    @enforce_keys [:from, :element, :pad]
    defstruct @enforce_keys
  end

  defmodule EndOfStream do
    @moduledoc """
    Message sent when some element of the pipeline receives the start of stream event on some pad.
    """

    @typedoc @moduledoc
    @type t :: %__MODULE__{
            from: pid(),
            element: Membrane.Element.name(),
            pad: Membrane.Pad.name()
          }

    @enforce_keys [:from, :element, :pad]
    defstruct @enforce_keys
  end

  defmodule Notification do
    @moduledoc """
    Message sent when the some element of the pipeline receives a notification.
    """

    @typedoc @moduledoc
    @type t :: %__MODULE__{
            from: pid(),
            element: Membrane.Element.name(),
            data: Membrane.ParentNotification.t()
          }

    @enforce_keys [:from, :element, :data]
    defstruct @enforce_keys
  end

  defmodule Terminated do
    @moduledoc """
    Message sent when the pipeline gracefully terminates.
    """

    @typedoc @moduledoc
    @type t :: %__MODULE__{from: pid()}

    @enforce_keys [:from]
    defstruct @enforce_keys
  end
end
