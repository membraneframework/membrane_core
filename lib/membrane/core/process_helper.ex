defmodule Membrane.Core.ProcessHelper do
  @moduledoc false
  require Membrane.Logger

  defguardp is_shutdown_tuple(reason)
            when is_tuple(reason) and tuple_size(reason) == 2 and elem(reason, 0) == :shutdown

  defguard is_silent_exit_reason(reason)
           when reason in [:normal, :shutdown] or is_shutdown_tuple(reason)

  @doc """
  This is a hack to exit with a custom reason, but without having GenServer
  exit logs occurring when the exit reason is neither :normal, :shutdown
  nor {:shutdown, reason}
  """
  @spec notoelo(any(), log?: boolean()) :: no_return()
  def notoelo(reason, opts \\ [])

  def notoelo(reason, log?: false) do
    do_notoelo(reason)
  end

  def notoelo(reason, _opts) when is_silent_exit_reason(reason) do
    do_notoelo(reason)
  end

  def notoelo(reason, _opts) do
    Membrane.Logger.error("Terminating with reason: #{inspect(reason)}")
    do_notoelo(reason)
  end

  defp do_notoelo(reason) do
    Process.flag(:trap_exit, false)
    Process.exit(self(), reason)
  end
end
