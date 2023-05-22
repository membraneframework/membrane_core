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

    def_output_pad :output,
      flow_control: :manual,
      accepted_format: _any,
      availability: :on_request

    def_input_pad :input,
      flow_control: :manual,
      demand_unit: :buffers,
      accepted_format: _any,
      availability: :on_request

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
