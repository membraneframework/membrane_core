defmodule Membrane.PipelineError do
  defexception [:message]
end

defmodule Membrane.BinError do
  defexception [:message]
end

defmodule Membrane.ParentError do
  defexception [:message]

  @impl true
  def exception(msg) when is_binary(msg), do: %__MODULE__{message: msg}

  def exception(not_child: module) do
    msg = """
    Child module "#{inspect(module)}" is neither Membrane Element nor Bin.
    Make sure that given module is the right one, implements proper behaviour
    and all needed dependencies are properly specified in the Mixfile.
    """

    %__MODULE__{message: msg}
  end
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
    val = Keyword.fetch!(opts, :value)

    msg = """
    Invalid value returned from #{inspect(module)}.#{inspect(fun)}:
    #{inspect(val, pretty: true)}
    """

    %__MODULE__{message: msg}
  end

  defp mk_exception(:not_implemented, {module, fun}, opts) do
    arity = Keyword.fetch!(opts, :arity)

    msg = """
    Callback #{fun}/#{arity} is not implemented in #{inspect(module)}
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

  defp format_reason({:invalid_component_playback, playback}) do
    "Cannot invoke this action while component playback is #{playback}."
  end

  defp format_reason(:actions_after_redemand) do
    "Redemand action has to be last in actions list."
  end

  defp format_reason({:unknown_action, doc_module}) do
    """
    We looked everywhere, but couldn't find out what this action is supposed to do.
    Make sure it's correct and valid for the component, its playback, callback or
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

defmodule Membrane.StreamFormatError do
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
