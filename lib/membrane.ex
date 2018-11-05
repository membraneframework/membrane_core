defmodule Membrane do
  use Application

  def start(_type, _args) do
    logger_config = Application.get_env(:membrane_core, Membrane.Logger, [])

    children = [
      {Membrane.Log.Router, {logger_config, name: Membrane.Log.Router}},
      {Membrane.Log.Supervisor, logger_config}
    ]

    opts = [strategy: :one_for_one, name: Membrane]
    Supervisor.start_link(children, opts)
  end
end
