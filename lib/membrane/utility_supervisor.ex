defmodule Membrane.UtilitySupervisor do
  @moduledoc """
  A supervisor that allows to start utility processes under the pipeline's
  supervision tree.

  The supervisor is spawned with each component and can be obtained from
  callback contexts.

  The supervisor never restarts any processes, it just makes sure they
  terminate when the component that started them terminates. If restarting
  is needed, a dedicated supervisor should be spawned under this supervisor, like

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

  Semantics of the `child_spec` argument is the same as in `Supervisor.child_spec/2`.
  """
  @spec start_child(t, Supervisor.child_spec() | {module(), term()} | module()) ::
          Supervisor.on_start_child()
  defdelegate start_child(supervisor, child_spec),
    to: Membrane.Core.SubprocessSupervisor,
    as: :start_utility

  @doc """
  Starts a process under the utility supervisor and links it to the current process.

  Semantics of the `child_spec` argument is the same as in `Supervisor.child_spec/2`.
  """
  @spec start_link_child(t, Supervisor.child_spec() | {module(), term()} | module()) ::
          Supervisor.on_start_child()
  defdelegate start_link_child(supervisor, child_spec),
    to: Membrane.Core.SubprocessSupervisor,
    as: :start_link_utility
end
