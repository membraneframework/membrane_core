defmodule Membrane.Pad.Mode do

  @callback handle_init() ::
    {:ok, any} |
    {:error, any}


  @callback handle_activate(pid, Membrane.Pad.direction_t, any) ::
    {:ok, any} |
    {:error, any}


  @callback handle_link(pid, Membrane.Pad.direction_t, any) ::
    {:ok, any} |
    {:error, any}


  @callback handle_call(any, pid, Membrane.Pad.direction_t, any) ::
    {:ok, any} |
    {:error, any}


  @callback handle_other(any, pid, Membrane.Pad.direction_t, any) ::
    {:ok, any} |
    {:error, any}


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Pad.Mode
    end
  end
end
