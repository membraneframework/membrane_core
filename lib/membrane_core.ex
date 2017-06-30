defmodule Membrane do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Membrane.Logger.Supervisor, []),
    ]

    opts = [strategy: :one_for_one, name: Membrane]
    Supervisor.start_link(children, opts)
  end
end
