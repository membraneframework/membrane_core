defmodule Membrane.Element.Base.Filter do
  @moduledoc """
  Base module to be used by all elements that are both sources and sinks.

  See `Membrane.Element.Base.Source` and `Membrane.Element.Base.Sink` for
  more information.
  """


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour
      use Membrane.Element.Base.Mixin.SourceBehaviour


      @doc false
      @spec is_source?() :: boolean
      def is_source?, do: true

      @doc false
      @spec is_sink?() :: boolean
      def is_sink?, do: true
    end
  end
end
