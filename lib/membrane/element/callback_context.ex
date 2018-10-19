defmodule Membrane.Element.CallbackContext do
  @moduledoc """
  Parent module for all contexts passed to callbacks.

  The idea of context is to provide access to commonly used information without
  holding it in elements state. Context differs depending on callback.
  """

  alias Membrane.Element.Pad
  alias Membrane.Core
  alias Core.Playback
  alias Core.Element.State
  use Bunch

  @macrocallback from_state(State.t(), keyword()) :: Macro.t()

  defmacro __using__(fields) do
    quote do
      default_fields_names = [:pads, :playback_state]
      fields_names = unquote(fields |> Keyword.keys())

      @type t :: %__MODULE__{
              unquote_splicing(fields),
              pads: %{Pad.ref_t() => Pad.Data.t()},
              playback_state: Playback.state_t()
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
          %unquote(__MODULE__){
            unquote_splicing(args),
            playback_state: unquote(state).playback.state,
            pads: unquote(state).pads.data
          }
        end
      end

      defoverridable unquote(__MODULE__)
    end
  end
end
