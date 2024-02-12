defmodule Membrane.Core.Parent do
  @moduledoc false

  @type state :: Membrane.Core.Bin.State.t() | Membrane.Core.Pipeline.State.t()

  @warn_whitelist [Membrane.Testing.Pipeline]

  @spec __after_compile__(Macro.Env.t(), binary()) :: any()
  def __after_compile__(env, _bytecode) do
    if env.module not in @warn_whitelist and Module.defines?(__MODULE__, {:handle_spec_started, 3}, :def) do
                  IO.warn("""
            Callback handle_spec_started/3 has been deprecated since :membrane_core v1.0.1, but it is implemented in #{inspect(__MODULE__)}
            """)
    end
  end
end
