defmodule Membrane.TemplatePipeline do
  @moduledoc """
  This is a generated template for a Pipeline. Uncomment the snippets as necessary.
  """
  use Membrane.Pipeline

  defmodule State do
    # Using this struct is not strictly necessary, but it's considered a good practice
    # and is strongly encouraged. Having a state with static fields with defined
    # typespecs adds robustness to the codebase and can prevent many bugs.
    @moduledoc false

    # When you add new fields to the struct remember to add them to this spec too.
    @type t :: %__MODULE__{}

    defstruct []
  end

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
  # def handle_setup(_ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_playing(_ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_info(message, _ctx, state) do
  #   Membrane.Logger.warning("""
  #   Received message but no handle_info callback has been specified. Ignoring.
  #   Message: #{inspect(message)}\
  #   """)
  #
  #   {[], state}
  # end

  # @impl true
  # def handle_child_setup_completed(_child, _ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_child_terminated(_child, _ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_child_playing(_child, _ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_element_start_of_stream(_element, _pad, _ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_element_end_of_stream(_element, _pad, _ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_child_notification(notification, element, _ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_crash_group_down(_group_name, _ctx, state) do
  #   {[], state}
  # end

  # @impl true
  # def handle_call(message, _ctx, state) do
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

  # @impl true
  # handle_child_pad_removed(element, pad, ctx, state) do
  #   ...
  # end
end
