defmodule Membrane.UtilitySupervisor do
  @moduledoc """
  A supervisor responsible for managing utility processes under the pipeline's
  supervision tree.

  The supervisor is spawned with each component and can be accessed from callback contexts.

  `Membrane.UtilitySupervisor` does not restart processes. Rather, it ensures that these utility processes
  terminate gracefully when the component that initiated them terminates.

  If a process needs to be able to restart, spawn a dedicated supervisor  under this supervisor.

  ## Example

      def handle_setup(ctx, state) do
        Membrane.UtilitySupervisor.start_link_child(
          ctx.utility_supervisor,
          {MySupervisor, children: [SomeWorker, OtherWorker], restart: :one_for_one})
      end

  """

  @typedoc """
  The pid of the `Membrane.UtilitySupervisor` process.
  """
  @type t :: pid()

  @doc """
  Starts a process under the utility supervisor.

  Semantics of the `child_spec` argument are the same as in `Supervisor.child_spec/2`.
  """
  @spec start_child(t, Supervisor.child_spec() | {module(), term()} | module()) ::
          Supervisor.on_start_child()
  defdelegate start_child(supervisor, child_spec),
    to: Membrane.Core.SubprocessSupervisor,
    as: :start_utility

  @doc """
  Starts a process under the utility supervisor and links it to the current process.

  Semantics of the `child_spec` argument are the same as in `Supervisor.child_spec/2`.
  """
  @spec start_link_child(t, Supervisor.child_spec() | {module(), term()} | module()) ::
          Supervisor.on_start_child()
  defdelegate start_link_child(supervisor, child_spec),
    to: Membrane.Core.SubprocessSupervisor,
    as: :start_link_utility
end
