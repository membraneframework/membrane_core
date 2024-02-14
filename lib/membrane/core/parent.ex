defmodule Membrane.Core.Parent do
  @moduledoc false

  @type state :: Membrane.Core.Bin.State.t() | Membrane.Core.Pipeline.State.t()

  @spec check_deprecated_callbacks(Macro.Env.t(), binary) :: :ok
  def check_deprecated_callbacks(env, _bytecode) do
    modules_whitelist = [Membrane.Testing.Pipeline]

    if env.module not in modules_whitelist and
         Module.defines?(env.module, {:handle_spec_started, 3}, :def) do
      warn_message = """
      Callback handle_spec_started/3 has been deprecated since \
      :membrane_core v1.1.0-rc0, but it is implemented in #{inspect(env.module)}
      """

      IO.warn(warn_message, [])
    end

    :ok
  end
end
