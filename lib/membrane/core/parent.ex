defmodule Membrane.Core.Parent do
  @moduledoc false

  @type state :: Membrane.Core.Bin.State.t() | Membrane.Core.Pipeline.State.t()

  defmacro bring_after_compile_check() do
    quote do
      @after_compile {__MODULE__, :__membrane_check_deprecated_functions__}

      def __membrane_check_deprecated_functions__(env, _bytecode) do
        modules_whitelist = [Membrane.Testing.Pipeline]

        if env.module not in modules_whitelist and
             Module.defines?(env.module, {:handle_spec_started, 3}, :def) do
          warn_message = """
          Callback handle_spec_started/3 has been deprecated since \
          :membrane_core v1.0.1, but it is implemented in #{inspect(env.module)}
          """

          IO.warn(warn_message, [])
        end
      end
    end
  end
end
