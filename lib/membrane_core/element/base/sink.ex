defmodule Membrane.Element.Base.Sink do

  @doc """
  Callback that is called when buffer should be written by the sink.

  It is safe to use blocking writes in the sink. It will cause limiting
  throughput of the pipeline to the capability of the sink.

  The arguments are:

  * name of the pad receiving a buffer,
  * buffer,
  * current element's state.
  """
  @callback handle_write(any, list(Membrane.Buffer.t), Membrane.Element.Context.Write.t, any) ::
    Membrane.Element.Base.Mixin.CommonBehaviour.callback_return_t


  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Element.Base.Mixin.CommonBehaviour
      use Membrane.Element.Base.Mixin.SinkBehaviour
      @behaviour Membrane.Element.Base.Sink

      @doc """
      Returns module that manages this element.
      """
      @spec manager_module() :: module
      def manager_module, do: Membrane.Element.Manager.Sink


      # Default implementations

      @doc false
      def handle_write1(_pad, _buffer, _context, state), do:
        {{:error, :handle_demand_not_implemented}, state}

      @doc false
      def handle_write(pad, buffers, context, state) do
        buffers |> Membrane.Element.Manager.Common.reduce_something1_results(state, fn buf, st ->
            handle_write1 pad, buf, context, st
          end)
      end


      defoverridable [
        handle_write: 4,
        handle_write1: 4,
      ]
    end
  end
end
