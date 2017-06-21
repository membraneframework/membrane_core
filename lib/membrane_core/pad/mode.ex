defmodule Membrane.Pad.Mode do
  @moduledoc false


  @callback handle_init() ::
    {:ok, any} |
    {:error, any}


  @callback handle_activate(pid, Membrane.Pad.direction_t, any) ::
    {:ok, any} |
    {:error, any}


  @callback handle_deactivate(pid, Membrane.Pad.direction_t, any) ::
    {:ok, any} |
    {:error, any}


  @callback handle_link(pid, Membrane.Pad.direction_t, any) ::
    {:ok, any} |
    {:error, any}


  @callback handle_call(any, pid, pid, Pad.name_t, Membrane.Pad.direction_t, any) ::
    {:ok, any} |
    {:error, any}


  @callback handle_other(any, pid, pid, Pad.name_t,  Membrane.Pad.direction_t, any) ::
    {:ok, any} |
    {:error, any}


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Pad.Mode


      # Default implementations

      @doc false
      def handle_init, do: {:ok, %{}}

      @doc false
      def handle_activate(_peer, _direction, state), do: {:ok, state}

      @doc false
      def handle_deactivate(_peer, _direction, state), do: {:ok, state}

      @doc false
      def handle_link(_peer, _direction, state), do: {:ok, state}

      @doc false
      def handle_other(_message, _parent, _peer, _name, _direction, state), do: {:ok, state}

      defoverridable [
        handle_init: 0,
        handle_activate: 3,
        handle_deactivate: 3,
        handle_link: 3,
        handle_other: 6,
      ]
    end
  end
end
