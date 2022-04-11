defmodule Membrane.RemoteStream do
  @moduledoc """
  Format describing an unparsed data stream. It should be used whenever outputting
  or accepting an unknown stream (not to be confused with _any_ stream, which
  can have well-specified format either), or a stream whose format can't/shouldn't
  be created at that stage.

  Parameters:
  - `:content_format` - format that is supposed to be carried in the stream,
  `nil` if unknown (default)
  - `:type` - either `:bytestream` (continuous stream) or `:packetized` (each buffer
  contains exactly one specified unit of data)
  """
  @type t :: %__MODULE__{
          content_format: module | nil,
          type: :bytestream | :packetized
        }
  defstruct content_format: nil, type: :bytestream
end
