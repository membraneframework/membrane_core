defmodule Membrane do
  use Application

  def start(_, _) do
    Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__)
  end
end
