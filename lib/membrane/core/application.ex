defmodule Membrane.Core.Application do
  use Application

  def start(_type, _args) do
    Membrane.Core.Metrics.init()
    Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__)
  end
end
