defmodule Membrane.Support.LogMetadataTest.Pipeline do
  @moduledoc """
  Pipeline used to test log metadata.
  Returns `Membrane.ChildrenSpec` containing `:log_metadata`.
  """
  use Membrane.Pipeline

  defmodule MetadataNotifyingElement do
    @moduledoc """
    Element that notifies the parent with its logger metadata immediately after init.
    """

    use Membrane.Filter

    import Membrane.ChildrenSpec

    require Membrane.Logger

    def_output_pad :output, accepted_format: _any

    def_input_pad :input, demand_unit: :buffers, accepted_format: _any

    @impl true
    def handle_init(_ctx, _opts) do
      {[notify_parent: Logger.metadata()], %{}}
    end
  end

  @impl true
  def handle_init(_ctx, opts) do
    actions =
      opts.elements
      |> Enum.map(fn {element_name, element_metadata} ->
        {:spec,
         {child(element_name, MetadataNotifyingElement), log_metadata: [test: element_metadata]}}
      end)

    {actions, %{}}
  end
end
