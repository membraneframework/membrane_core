defmodule Membrane.Parent.CallbackContext do
  alias Membrane.Core
  alias Core.Element
  alias Core.Bin
  use Bunch

  @macrocallback from_state(Element.State.t() | Bin.State.t(), keyword()) :: Macro.t()

  defmacro __using__(fields) do
    quote do
      default_fields_names = [
        :playback_state
        #  ? :clock
      ]

      fields_names = unquote(fields |> Keyword.keys())

      @type t :: %__MODULE__{
              unquote_splicing(fields),
              playback_state: Membrane.PlaybackState.t()
            }

      @behaviour unquote(__MODULE__)

      @enforce_keys Module.get_attribute(__MODULE__, :enforce_keys)
                    ~> (&1 || fields_names)
                    |> Bunch.listify()
                    ~> (&1 ++ default_fields_names)

      defstruct fields_names ++ default_fields_names

      @impl true
      defmacro from_state(state, args \\ []) do
        quote do
          state = unquote(state)

          %unquote(__MODULE__){
            unquote_splicing(args),
            playback_state: state.playback.state
            # clock: state.clock_provider.clock
          }
        end
      end

      defoverridable unquote(__MODULE__)
    end
  end
end
