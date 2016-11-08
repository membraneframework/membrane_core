defmodule Membrane.Element.Base.Mixin.Process do
  @moduledoc """
  This module is a mixin with common routines regarding spawning element
  as a process.

  You should not use this directly unless you know what are you doing
  """


  @doc """
  Callback invoked when element is initialized. It will receive options
  passed to start_link.
  """
  @callback handle_prepare(any) ::
    {:ok, any} |
    {:error, any}


  defmacro __using__(_) do
    quote do
      use GenServer


      def start_link(options) do
        GenServer.start_link(__MODULE__, options)
      end


      def init(options) do
        {:ok, element_state} = __MODULE__.handle_prepare(options)
        # TODO handle errors
        
        {:ok, %{
          element_state: element_state
        }}
      end


      # Default implementations

      def handle_prepare(_options), do: %{}


      defoverridable [
        handle_prepare: 1
      ]
    end
  end
end
