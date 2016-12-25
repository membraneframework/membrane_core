defmodule Membrane.Element.Core.CapsOverrideOptions do
  defstruct \
    caps: nil

  @type t :: %Membrane.Element.Core.CapsOverrideOptions{
    caps: map | nil
  }
end
