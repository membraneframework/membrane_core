defmodule Membrane do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    logger_config = Application.get_env(:membrane_core, Membrane.Logger, [])

    children = [
      worker(Membrane.Log.Router, [logger_config, [name: Membrane.Log.Router]], [id: Membrane.Log.Router]),
      supervisor(Membrane.Log.Supervisor, [logger_config]),
    ]

    opts = [strategy: :one_for_one, name: Membrane]
    Supervisor.start_link(children, opts)
  end
end
