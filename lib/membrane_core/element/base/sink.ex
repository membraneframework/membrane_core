defmodule Membrane.Element.Base.Sink do
  @moduledoc """
  This module should be used by all elements that are sources.
  """


  @doc """
  Callback that is called when buffer arrives.

  The arguments are:

  - caps
  - data
  - current element state

  While implementing these callbacks, please use pattern matching to define
  what caps are supported. In other words, define one function matching this
  signature per each caps supported.
  """
  @callback handle_buffer(%Membrane.Caps{}, bitstring, any) ::
    {:ok, any} |
    {:error, any}


  defmacro __using__(_) do
    quote do
      @behaviour Membrane.Element.Base.Sink

      use Membrane.Element.Base.Mixin.Process


      @doc """
      Callback invoked on incoming buffer.

      Will delegate actual processing to handle_buffer/3.
      """
      def handle_info({:membrane_buffer, {caps, data}}, %{element_state: element_state} = state) do
        # debug("Incoming buffer: caps = #{inspect(caps)}, byte_size(data) = #{byte_size(data)}, data = #{inspect(data)}")

        case handle_buffer(caps, data, element_state) do
          {:ok, new_element_state} ->
            {:noreply, %{state | element_state: new_element_state}}

          # TODO handle errors
        end
      end
    end
  end
end
