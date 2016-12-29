defmodule Membrane.Element.Base.Source do
  @moduledoc """
  Base module to be used by all elements that are sources.

  The simplest possible source element looks like the following:

      defmodule Membrane.Element.Sample.Source do
        use Membrane.Element.Base.Source

        def_known_source_pads %{
          :sink => {:always, :any}
        }

        # Private API

        @doc false
        def handle_init(_options) do
          {:ok, %{}}
        end
      end
  """


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SourceBehaviour
    end
  end
end
