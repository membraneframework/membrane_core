defmodule Membrane.PipelineError do
  defexception [:message]
end

defmodule Membrane.CallbackError do
  defexception [:message]

  @impl true
  def exception(opts) do
    kind = Keyword.fetch!(opts, :kind)
    callback = Keyword.fetch!(opts, :callback)
    mk_exception(kind, callback, opts)
  end

  defp mk_exception(:bad_return, {module, fun}, opts) do
    val = Keyword.fetch!(opts, :val)

    msg = """
    Invalid value returned from #{inspect(module)}.#{inspect(fun)}:
    #{inspect(val, pretty: true)}
    """

    %__MODULE__{message: msg}
  end

  defp mk_exception(:invalid_action, {module, fun}, opts) do
    action = Keyword.fetch!(opts, :action)

    msg = """
    Invalid action returned from #{inspect(module)}.#{inspect(fun)}:
    #{inspect(action, pretty: true)}
    """

    %__MODULE__{message: msg}
  end

  defp mk_exception(:error, {module, fun}, opts) do
    reason = Keyword.fetch!(opts, :reason)

    msg = """
    Error returned from #{inspect(module)}.#{inspect(fun)}:
    #{inspect(reason, pretty: true)}
    """

    %__MODULE__{message: msg}
  end
end

defmodule Membrane.ElementLinkError do
  defexception [:message]
end
