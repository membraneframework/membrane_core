defmodule Membrane.Element.Base.Filter do
  alias Membrane.{Buffer, Element}
  alias Element.Base.Mixin
  alias Element.{Context, Pad}
  @doc """
  Callback that is called when buffer arrives.

  The arguments are:
    - name of the pad receiving a buffer,
    - buffer,
    - context (`Membrane.Element.Context.Process`)
    - current element state.
  """
  @callback handle_process(Pad.name_t, list(Buffer.t), Context.Process.t, any) ::
    Mixin.CommonBehaviour.callback_return_t

  @callback handle_process1(Pad.name_t, Buffer.t, Context.Process.t, any) ::
    Mixin.CommonBehaviour.callback_return_t


  defmacro __using__(_) do
    quote location: :keep do
      use Mixin.CommonBehaviour
      use Mixin.SourceBehaviour
      use Mixin.SinkBehaviour
      @behaviour unquote(__MODULE__)

      @doc """
      Returns module that manages this element.
      """
      @spec manager_module() :: module
      @impl true
      def manager_module, do: Membrane.Element.Manager.Filter

      # Default implementations

      @doc false
      @impl true
      def handle_caps(_pad, caps, _context, state), do: {{:ok, forward: caps}, state}

      @doc false
      @impl true
      def handle_event(_pad, event, _context, state), do: {{:ok, forward: event}, state}

      @doc false
      @impl true
      def handle_demand(_pad, _size, _unit, _context, state), do:
        {{:error, :handle_demand_not_implemented}, state}

      @doc false
      @impl true
      def handle_process1(_pad, _buffer, _context, state), do:
        {{:error, :handle_process_not_implemented}, state}

      @doc false
      @impl true
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
