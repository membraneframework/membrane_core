defmodule Membrane.Element.CallbackContext do
  @moduledoc """
  Parent module for all contexts passed to callbacks
  """

  use Bunch

  @macrocallback from_state(Membrane.Core.Element.State.t(), keyword()) :: Macro.t()

  defmacro __using__(fields) do
    quote do
      @behaviour unquote(__MODULE__)

      default_fields_names = [:pads, :playback_state]
      fields_names = unquote(fields |> Keyword.keys())

      @enforce_keys Module.get_attribute(__MODULE__, :enforce_keys)
                    ~> (&1 || fields_names)
                    |> Bunch.listify()
                    ~> (&1 ++ default_fields_names)

      @type t :: %__MODULE__{
              unquote_splicing(fields),
              pads: %{Pad.ref_t() => Membrane.Element.Pad.Data.t()},
              playback_state: Membrane.Core.Playback.state_t()
            }

      defstruct fields_names ++ default_fields_names

      @impl true
      defmacro from_state(state, entries \\ []) do
        quote do
          %unquote(__MODULE__){
            unquote_splicing(entries),
            playback_state: unquote(state).playback.state,
            pads: unquote(state).pads.data
          }
        end
      end
    end
  end
end
