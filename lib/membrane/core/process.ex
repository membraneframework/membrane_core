defmodule Membrane.Core.Process do
  @moduledoc false

  require Membrane.Logger

  @spec exit_self(any(), log?: boolean()) :: no_return()
  def exit_self(reason, opts \\ []) do
    log? = Keyword.get(opts, :log?, false)

    case reason do
      _any when not log? -> :ok
      :normal -> :ok
      :shutdown -> :ok
      {:shutdown, _reason} -> :ok
      _reason -> Membrane.Logger.error("Terminating with reason: #{inspect(reason)}")
    end

    # this is a hack to exit with a custom reason, but without having GenServer
    # exit logs occurring when the exit reason is neither :normal, :shutdown
    # nor {:shutdown, reason}
    Process.flag(:trap_exit, false)
    Process.exit(self(), reason)
  end
end
