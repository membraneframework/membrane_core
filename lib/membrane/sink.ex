defmodule Membrane.Sink do
  @moduledoc """
  Module defining behaviour for sinks - elements consuming data.

  Behaviours for sinks are specified, besides this place, in modules
  `Membrane.Element.Base`,
  and `Membrane.Element.WithInputPads`.

  Sink elements can define only input pads. Job of a usual sink is to receive some
  data on such pad and consume it (write to a soundcard, send through TCP etc.).
  If the pad has the flow control set to `:manual`, then element is also responsible
  for requesting demands when it is able and willing to consume data (for more details,
  see `t:Membrane.Element.Action.demand/0`). Sinks, like all elements, can of course
  have multiple pads if needed to provide more complex solutions.
  """

  alias Membrane.Core.DocsHelper

  @doc """
  Brings all the stuff necessary to implement a sink element.

  Options:
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
  """
  defmacro __using__(options) do
    Module.put_attribute(__CALLER__.module, :__membrane_element_type__, :sink)

    quote location: :keep do
      use Membrane.Element.Base, unquote(options)
      use Membrane.Element.WithInputPads

      @doc false
      @spec membrane_element_type() :: Membrane.Element.type()
      def membrane_element_type, do: :sink

      @impl true
      def handle_buffer(pad, buffer, ctx, state) do
        apply(__MODULE__, :handle_write, [pad, buffer, ctx, state])
      end

      @impl true
      def handle_buffers_batch(pad, buffers, ctx, state) do
        apply(__MODULE__, :handle_write_list, [pad, buffers, ctx, state])
      end

      @impl true
      def handle_write_list(pad, buffers, ctx, state) do
        args_list = buffers |> Enum.map(&[pad, &1])
        {[split: {:handle_buffer, args_list}], state}
      end

      defoverridable handle_buffer: 4,
                     handle_buffers_batch: 4,
                     handle_write_list: 4
    end
  end

  DocsHelper.add_callbacks_list_to_moduledoc(
    __MODULE__,
    [Membrane.Element.Base, Membrane.Element.WithInputPads]
  )
end
