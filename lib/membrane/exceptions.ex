defmodule Membrane.PipelineError do
  defexception [:message]
end

defmodule Membrane.ParentError do
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
    Invalid action returned from #{inspect(module)}.#{to_string(fun)}:
    #{inspect(action, pretty: true)}\
    """

    %__MODULE__{message: msg}
  end

  defp mk_exception(:error, {module, fun}, opts) do
    reason = Keyword.fetch!(opts, :reason)

    state =
      case Keyword.fetch(opts, :state) do
        {:ok, state} -> "Internal state: #{inspect(state, pretty: true)}"
        :error -> ""
      end

    msg = """
    Error returned from #{inspect(module)}.#{fun}:
    #{inspect(reason, pretty: true)}
    #{state}
    """

    %__MODULE__{message: msg}
  end
end

defmodule Membrane.ActionError do
  defexception [:message]

  @impl true
  def exception(opts) do
    action = Keyword.fetch!(opts, :action)
    reason = Keyword.fetch!(opts, :reason)

    msg = """
    Error while handling action #{inspect(action, pretty: true)}
    #{format_reason(reason)}
    """

    %__MODULE__{message: msg}
  end

  defp format_reason({:invalid_callback, callback}) do
    "This action cannot be returned from the #{callback} callback."
  end

  defp format_reason({:invalid_playback_state, playback_state}) do
    "Cannot invoke this action in #{playback_state} state."
  end

  defp format_reason(:actions_after_redemand) do
    "Redemand action has to be last in actions list."
  end

  defp format_reason(:unknown_action) do
    """
    We looked everywhere, but couldn't find out what this action is supposed to do.
    Make sure it's correct and valid for the component, callback, playback state or
    other possible circumstances.\
    """
  end
end

defmodule Membrane.LinkError do
  defexception [:message]
end

defmodule Membrane.ElementError do
  defexception [:message]
end

defmodule Membrane.TimerError do
  defexception [:message]
end
