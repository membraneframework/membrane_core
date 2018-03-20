defmodule Membrane.Element.Base.Filter do
  @doc """
  Callback that is called when buffer arrives.

  The arguments are:
    - name of the pad receiving a buffer,
    - buffer,
    - context (`Membrane.Element.Context.Process`)
    - current element state.
  """
  @callback handle_process(
              any,
              list(Membrane.Buffer.t()),
              Membrane.Element.Context.Process.t(),
              any
            ) :: Membrane.Element.Base.Mixin.CommonBehaviour.callback_return_t()

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SourceBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour
      @behaviour Membrane.Element.Base.Filter

      @doc """
      Returns module that manages this element.
      """
      @spec manager_module() :: module
      def manager_module, do: Membrane.Element.Manager.Filter

      # Default implementations

      @doc false
      def handle_caps(_pad, caps, _context, state), do: {{:ok, forward: caps}, state}

      @doc false
      def handle_event(_pad, event, _context, state), do: {{:ok, forward: event}, state}

      @doc false
      def handle_demand(_pad, _size, _unit, _context, state),
        do: {{:error, :handle_demand_not_implemented}, state}

      @doc false
      def handle_process1(_pad, _buffer, _context, state),
        do: {{:error, :handle_process_not_implemented}, state}

      @doc false
      def handle_process(pad, buffers, context, state) do
        args_list = buffers |> Enum.map(&[pad, &1, context])
        {{:ok, split: {:handle_process1, args_list}}, state}
      end

      defoverridable handle_caps: 4,
                     handle_event: 4,
                     handle_demand: 5,
                     handle_process: 4,
                     handle_process1: 4
    end
  end
end
