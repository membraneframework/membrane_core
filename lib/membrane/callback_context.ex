defmodule Membrane.CallbackContext do
  alias Membrane.Core
  alias Core.Element
  alias Core.Bin
  alias Core.Pipeline

  @callback default_fields_names :: list(atom)
  @callback default_fields_spec :: list
  @callback default_ctx_assigment(any) :: list

  defmacro __using__(_opts) do
    quote do
      alias Membrane.Pad
      alias Membrane.Core
      alias Core.Element
      alias Core.Bin
      alias Core.Pipeline
      use Bunch

      @behaviour unquote(__MODULE__)

      @impl true
      def default_fields_names() do
        []
      end

      @impl true
      def default_fields_spec() do
        quote do
          []
        end
      end

      @impl true
      def default_ctx_assigment(_state) do
        quote do
          []
        end
      end

      defoverridable unquote(__MODULE__)

      @macrocallback from_state(Element.State.t() | Bin.State.t() | Pipeline.State.t(), keyword()) ::
                       Macro.t()

      defmacro __using__(fields) do
        quote do
          require unquote(__MODULE__)
          @behaviour unquote(__MODULE__)

          fields_names = unquote(fields |> Keyword.keys())

          @enforce_keys Module.get_attribute(__MODULE__, :enforce_keys)
                        ~> (&1 || fields_names)
                        |> Bunch.listify()
                        ~> (&1 ++ unquote(__MODULE__).default_fields_names())

          defstruct fields_names ++ unquote(__MODULE__).default_fields_names()

          @impl true
          defmacro from_state(state, args \\ []) do
            require unquote(__MODULE__)
            alias unquote(__MODULE__), as: ModuleInBetween

            quote do
              state = unquote(state)
              require unquote(ModuleInBetween)

              %unquote(__MODULE__){
                unquote_splicing(ModuleInBetween.default_ctx_assigment(state) ++ args)
              }
            end
          end

          defoverridable unquote(__MODULE__)
        end
      end
    end
  end
end
