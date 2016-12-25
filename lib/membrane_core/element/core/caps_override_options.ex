defmodule Membrane.Element.Core.CapsOverrideOptions do
  @moduledoc """
  Structure representing possible options for `Membrane.Element.Core.CapsOverride`. 
  """

  defstruct \
    caps: nil

  @type t :: %Membrane.Element.Core.CapsOverrideOptions{
    caps: map | nil
  }
end
