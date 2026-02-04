defmodule Membrane.TemplateEndpoint do
  @moduledoc """
  This is a generated template for an Endpoint. Uncomment the snippets as necessary.
  """
  use Membrane.Endpoint

  # def_input_pad :input,
  #   accepted_format: _any,
  #   availability: :on_request | :always,
  #   max_instances: positive integer,
  #   flow_control: :manual | :auto | :push,
  #   demand_unit: :buffers | :bytes,
  #   options: [
  #      Same structure as in def_options/1
  #   ]

  # def_output_pad :output,
  #   accepted_format: _any,
  #   availability: :on_request | :always,
  #   max_instances: positive integer,
  #   flow_control: :manual | :auto | :push,
  #   demand_unit: :buffers | :bytes,
  #   options: [
  #      Same structure as in def_options/1
  #   ]

  # def_options some_option: [
  #               spec: typespec of the option,
  #               default: default value,
  #               inspector: function converting fields' value to a string for documentation purposes (optional),
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

  # Important: this callback only needs to be implemented when any output pads operate
  # in `:manual` flow control.
  # @impl true
  # def handle_demand(pad, size, unit, context, state) do
  #   ...
  # end

  # ----------------------------------------------
  # --- CALLBACKS WITH DEFAULT IMPLEMENTATIONS ---
  # ----------------------------------------------

  # Note: by default this callback will return with state set to an empty map %{},
  # however we recommend using a dedicated State struct.
  @impl true
  def handle_init(_ctx, opts) do
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

  # @impl true
  # def handle_pad_added(_pad, _context, state) do
  #   {[], state}
  # end

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

  # --------------------------
  # --- OPTIONAL CALLBACKS ---
  # --------------------------

  # @impl true
  # def handle_tick(timer_id, context, state) do
  #   ...
  # end
end
