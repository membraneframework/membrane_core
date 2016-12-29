defmodule Membrane.Element.Base.Sink do
  @moduledoc """
  Base module to be used by all elements that are sinks.

  The simplest possible sink element looks like the following:

      defmodule Membrane.Element.Sample.Sink do
        use Membrane.Element.Base.Sink

        def_known_sink_pads %{
          :sink => {:always, :any}
        }

        # Private API

        @doc false
        def handle_init(_options) do
          {:ok, %{}}
        end

        @doc false
        def handle_buffer(_buffer, state) do
          {:ok, state}
        end
      end
  """


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour
    end
  end
end
