defmodule Membrane.Element.Base.Sink do
  @moduledoc """
  Base module to be used by all elements that are sinks.
  """


  defmacro __using__(_) do
    quote location: :keep do
      # Order here is important
      #
      # Calls have to be near each other
      # Infos have to be near each other
      #
      # ...because elixir requires that different pattern matching functions
      # have to be in a sequence.
      use Membrane.Element.Base.Mixin.CommonFuncs
      use Membrane.Element.Base.Mixin.CommonProcess
      use Membrane.Element.Base.Mixin.CommonCalls

      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour

      # Sink handle_info are more specific than common handle_info
      # so they should be first
      use Membrane.Element.Base.Mixin.SinkInfos
      use Membrane.Element.Base.Mixin.CommonInfos
    end
  end
end
