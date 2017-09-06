defmodule Membrane.Element.Base.Filter do

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SourceBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour


      @doc """
      Returns module on which this Element is based.
      """
      @spec base_module() :: module
      def base_module, do: Membrane.Element.Manager.Filter


      # Default implementations

      @doc false
      def handle_new_pad(_pad, _direction, _params, state), do: {:error, :adding_pad_unsupported}

      @doc false
      def handle_pad_added(_pad, _direction, state), do: {:ok, state}

      @doc false
      def handle_pad_removed(_pad, state), do: {:ok, state}

      @doc false
      def handle_caps(_pad, _caps, _params, state), do: {{:ok, forward: :all}, state}

      @doc false
      def handle_event(_pad, _event, _params, state), do: {{:ok, forward: :all}, state}

      @doc false
      def handle_demand(_pad, _size, _unit, _params, state), do:
        {{:error, :handle_demand_not_implemented}, state}

      @doc false
      def handle_process1(_pad, _buffer, _params, state), do: {:ok, state}

      @doc false
      def handle_process(pad, buffers, params, state) do
        buffers |> Membrane.Element.Manager.Common.reduce_something1_results(state, fn b, st ->
            handle_process1 pad, b, params, st
          end)
      end


      defoverridable [
        handle_new_pad: 4,
        handle_pad_added: 3,
        handle_pad_removed: 2,
        handle_caps: 4,
        handle_event: 4,
        handle_demand: 5,
        handle_process: 4,
        handle_process1: 4,
      ]
    end
  end
end
