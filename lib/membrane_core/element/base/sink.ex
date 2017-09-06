defmodule Membrane.Element.Base.Sink do

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour


      @doc """
      Returns module on which this Element is based.
      """
      @spec base_module() :: module
      def base_module, do: Membrane.Element.Manager.Sink


      # Default implementations

      @doc false
      def handle_new_pad(_pad, _params, state), do: {:error, :adding_pad_unsupported}

      @doc false
      def handle_pad_added(_pad, state), do: {:ok, state}

      @doc false
      def handle_pad_removed(_pad, state), do: {:ok, state}

      @doc false
      def handle_caps(_pad, _caps, _params, state), do: {:ok, state}

      @doc false
      def handle_event(_pad, _event, _params, state), do: {:ok, state}

      @doc false
      def handle_write1(_pad, _buffer, _params, state), do: {:ok, state}

      @doc false
      def handle_write(pad, buffers, params, state) do
        buffers |> Membrane.Element.Manager.Common.reduce_something1_results(state, fn buf, st ->
            handle_write1 pad, buf, params, st
          end)
      end


      defoverridable [
        handle_new_pad: 3,
        handle_pad_added: 2,
        handle_pad_removed: 2,
        handle_caps: 4,
        handle_event: 4,
        handle_write: 4,
        handle_write1: 4,
      ]
    end
  end
end
