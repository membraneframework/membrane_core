defmodule Membrane.Core.CallbackContext do
  @moduledoc false

  @callback extract_default_fields(state :: Macro.t(), args :: keyword(Macro.t())) ::
              keyword(Macro.t())

  defmacro __using__(default_fields) do
    quote do
      @behaviour unquote(__MODULE__)

      @type default_fields :: %{unquote_splicing(default_fields)}

      @impl true
      def extract_default_fields(_state, args) do
        args
      end

      defoverridable unquote(__MODULE__)

      @macrocallback from_state(state :: Macro.t(), args :: keyword(Macro.t())) :: Macro.t()

      unquote(nested_using({:quote, [], [[do: default_fields]]}))
    end
  end

  defp nested_using(default_fields) do
    quote do
      defmacro __using__(fields) do
        default_fields = unquote(default_fields)

        quote do
          require unquote(__MODULE__)
          @behaviour unquote(__MODULE__)

          @type t :: %__MODULE__{unquote_splicing(fields ++ default_fields)}

          fields_names = unquote(Keyword.keys(fields))
          default_fields_names = unquote(Keyword.keys(default_fields))

          @enforce_keys Module.get_attribute(__MODULE__, :enforce_keys, fields_names) ++
                          default_fields_names

          defstruct fields_names ++ default_fields_names

          @impl true
          defmacro from_state(state, args \\ []) do
            module = unquote(__MODULE__)

            quote do
              require unquote(module)

              %unquote(__MODULE__){
                unquote_splicing(module.extract_default_fields(state, args))
              }
            end
          end

          defoverridable unquote(__MODULE__)
        end
      end
    end
  end
end
