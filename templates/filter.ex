defmodule Membrane.TemplateFilter do
  @moduledoc """
  This is a generated template for a Membrane.Filter. Uncomment the snippets as necessary.
  """
  use Membrane.Filter

  def_input_pad :input,
    accepted_format: _any,
    flow_control: :auto # | :manual | :push,
  #   availability: :on_request | :always, # default - :always
  #   max_instances: pos_integer() | :infinity, # relevant only for dynamic pads, default - :infinity
  #   demand_unit: :buffers | :bytes, # When using :manual flow control, this needs to be provided
  #   options: [
  #      Same structure as in def_options/1
  #   ]

  def_output_pad :output,
    accepted_format: _any,
    flow_control: :push # | :manual | :auto,
  #   availability: :on_request | :always, # default - :always
  #   max_instances: pos_integer() | :infinity, # relevant only for dynamic pads, default - :infinity
  #   demand_unit: :buffers | :bytes, 
  #   options: [
  #      Same structure as in def_options/1
  #   ]

  # This macro also defines a struct of this module, which is then used for providing options
  # when instantiating this component.
  # def_options some_option: [
  #               spec: typespec of the option.
  #               default: default value - if not set, providing this option will be mandatory.
  #               inspector: function converting fields' value to a string for documentation purposes. If not set, &inspect/1 will be used.
  #               description: """
  #               Desription of the option.
  #               """
  #             ]

  defmodule State do
    # Using this struct is not strictly necessary, but it's considered a good practice
    # and is strongly encouraged. Having a state with static fields with defined
    # typespecs adds robustness to the codebase and can prevent many bugs.
    @moduledoc false

    # When you add new fields to the struct remember to add them to this spec too.
    @type t :: %__MODULE__{}

    defstruct []
  end

  # -----------------
  # --- CALLBACKS ---
  # -----------------
  # These callbacks have been ordered as they are usually being executed in the lifecycle
  # of a typical Membrane component - see https://hexdocs.pm/membrane_core/components_lifecycle.html.
  # Most of them are optional and have default implementations, which are present here as commented out code.
  # Any exceptions to this rule are mentioned above the relevant callbacks.

  # By default this callback will return with state set to an empty map %{},
  # however we recommend using a dedicated State struct.
  @impl true
  def handle_init(_ctx, _opts) do
    {[], %State{}}
  end

  # @impl true
  # def handle_setup(_context, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_playing(_context, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_info(message, _context, state) do
  #   Membrane.Logger.warning("""
  #   Received message but no handle_info callback has been specified. Ignoring.
  #   Message: #{inspect(message)}\
  #   """)
  #
  #   {[], state}
  # end

  # This callback will be executed only for dynamic pads.
  # @impl true
  # def handle_pad_added(_pad, _context, state) do
  #   {[], state}
  # end

  # This callback will be executed only for dynamic pads.
  # @impl true
  # def handle_pad_removed(_pad, _context, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_stream_format(_pad, _stream_format, _context, state) do
  #   {[], state}
  # end
  
  # @impl true
  # def handle_start_of_stream(_pad, _context, state) do
  #   {[], state}
  # end

  # This callback doesn't have a default implementation. The one present
  # here forwards all buffers received without doing anything else.
  @impl true
  def handle_buffer(_pad, buffer, _ctx, state) do
    {[forward: buffer], state}
  end
  
  # Important: this callback needs to be implemented when any output pads operate
  # in `:manual` flow control.
  # @impl true
  # def handle_demand(pad, size, unit, context, state) do
  #   ...
  # end

  # @impl true
  # def handle_event(_pad, _event, _context, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_parent_notification(_notification, _ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_end_of_stream(_pad, _context, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_terminate_request(_ctx, state) do
  #   {[terminate: :normal], state}
  # end

  # This callback doesn't have a default implementation, but will be called only 
  # if a `:start_timer` action has been executed. For more information and examples 
  # of timer usage see https://hexdocs.pm/membrane_core/timer.html.
  # @impl true
  # def handle_tick(timer_id, context, state) do
  #   ...
  # end
end
