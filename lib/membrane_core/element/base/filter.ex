defmodule Membrane.Element.Base.Filter do
  @moduledoc """
  This module should be used by all elements that are both sources and sinks.
  """


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonFuncs
      use Membrane.Element.Base.Mixin.CommonProcess
      use Membrane.Element.Base.Mixin.CommonCalls

      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour

      # Order here is important
      #
      # Calls have to be near each other
      # Infos have to be near each other
      #
      # ...because elixir requires that different pattern matching functions
      # have to be in a seqence.
      use Membrane.Element.Base.Mixin.SourceCalls

      use Membrane.Element.Base.Mixin.CommonInfos
      use Membrane.Element.Base.Mixin.SinkInfos
    end
  end
end
