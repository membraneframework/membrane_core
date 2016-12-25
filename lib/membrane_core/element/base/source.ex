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
      use Membrane.Element.Base.Mixin.SourceBehaviour

      use Membrane.Element.Base.Mixin.SourceCalls

      use Membrane.Element.Base.Mixin.CommonInfos
    end
  end
end
