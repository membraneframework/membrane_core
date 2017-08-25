defmodule Membrane.Helper.Timer do
  use Membrane.Helper
  require Membrane.Time, as: Time

  def send_at(time, pid \\ self(), msg) when Time.is_t(time) do
    time
        |> Kernel.-(Time.system_time)
        |> Time.to_milliseconds
        |> :timer.send_after(pid, msg)
  end

end
