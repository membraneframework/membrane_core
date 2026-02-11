defmodule Membrane.TemplatePipeline do
  @moduledoc """
  This is a generated template for a Membrane.Pipeline. Uncomment the snippets as necessary.
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

  # This callback doesn't have a default implementation, but will be called only 
  # if a `:start_timer` action has been executed. For more information and examples 
  # of timer usage see https://hexdocs.pm/membrane_core/timer.html.
  # @impl true
  # def handle_tick(timer_id, context, state) do
  #   ...
  # end

  # This callback doesn't have a default implementation and will be called only if 
  # a child removes it's own dynamic pad. If not implemented, the bin will crash. 
  # @impl true
  # handle_child_pad_removed(element, pad, ctx, state) do
  #   ...
  # end
end
