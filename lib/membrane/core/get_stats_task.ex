defmodule Membrane.Core.GetStatsTask do
  alias Membrane.Core.Message

  def run(child_pid, child_name) do
    monitor_ref = Process.monitor(child_pid)
    msg_ref = make_ref()

    Message.send(child_pid, :get_stats, [self(), msg_ref])

    receive do
      {:DOWN, ^monitor_ref, :process, ^child_pid, _reason} ->
        nil

      {:get_stats, ^msg_ref, stats} ->
        {child_name, stats}
    after
      1000 ->
        nil
    end
  end
end
