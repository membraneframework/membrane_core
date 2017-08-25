defmodule Membrane.Helper.Timer do
  use Membrane.Helper
  require Membrane.Time, as: Time

  def send_after(time, min_delay \\ nil, pid \\ self(), msg)
  when Time.is_t(time) and (is_nil(min_delay) or Time.is_t(min_delay)) and is_pid(pid)
  do
    time
      |> Kernel.-(Time.system_time)
      ~> (t -> if is_nil(min_delay) do t else max t, min_delay end)
      |> Time.to_milliseconds
      |> :timer.send_after(pid, msg)
  end

end
