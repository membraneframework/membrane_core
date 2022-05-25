defmodule Membrane.PipelineError do
  defexception [:message]
end

defmodule Membrane.ParentError do
  defexception [:message]
end

defmodule Membrane.UnknownChildError do
  defexception [:message]

  @impl true
  def exception(opts) do
    opts = Map.new(opts)

    msg = """
    Child of name #{inspect(opts.name)} doesn't exist. Available children are #{inspect(Map.keys(opts.children))}.
    """

    %__MODULE__{message: msg}
  end
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

  defp format_reason({:unknown_action, doc_module}) do
    """
    We looked everywhere, but couldn't find out what this action is supposed to do.
    Make sure it's correct and valid for the component, callback, playback state or
    other possible circumstances. See the docs for #{inspect(doc_module)} to check
    which actions are supported and when you can return them.
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

defmodule Membrane.PadError do
  defexception [:message]
end

defmodule Membrane.UnknownPadError do
  defexception [:message]

  @impl true
  def exception(opts) do
    pad = Keyword.fetch!(opts, :pad)
    module = Keyword.fetch!(opts, :module)
    %__MODULE__{message: "Unknown pad #{inspect(pad)} of #{inspect(module)}"}
  end
end

defmodule Membrane.PadDirectionError do
  defexception [:message]

  @impl true
  def exception(opts) do
    opts = Map.new(opts)

    %__MODULE__{
      message:
        "Sending #{opts.action} via pad #{inspect(opts.pad)} with #{opts.direction} direction is not allowed"
    }
  end
end
