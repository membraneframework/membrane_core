defmodule Membrane.StreamFormat do
  @moduledoc """
  Describes capabilities of some pad.

  Every pad has some capabilities, which define a type of data that pad is
  expecting. This format can be, for example, raw audio with specific sample
  rate or encoded audio in given format.

  To link two pads together, their capabilities have to be compatible.
  """
  @type t :: struct
end
