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

    msg = """
    Error returned from #{inspect(module)}.#{fun}:
    #{inspect(reason, pretty: true)}
    """

    %__MODULE__{message: msg}
  end
end

defmodule Membrane.ActionError do
  defexception [:message]

  @impl true
  def exception(opts) do
    {action, args} = Keyword.fetch!(opts, :action)
    {module, fun} = Keyword.fetch!(opts, :callback)
    reason = Keyword.fetch!(opts, :reason)

    msg = """
    Error while handling #{inspect(action)} action:
    #{format_reason(reason)}
    Callback: #{inspect(module)}.#{fun}
    Action args: #{inspect(args, pretty: true)}\
    """

    %__MODULE__{message: msg}
  end

  defp format_reason({:playback_state, playback_state}) do
    "Cannot invoke this action in #{playback_state} state."
  end

  defp format_reason(:actions_after_redemand) do
    "Redemand action has to be last in actions list."
  end

  defp format_reason({:invalid_buffer, buffer}) do
    "Invalid buffer: #{inspect(buffer, pretty: true)}"
  end

  defp format_reason({:unknown_pad, pad}) do
    "The pad #{inspect(pad)} does not exist"
  end

  defp format_reason({:invalid_pad_dir, pad, dir}) do
    "Cannot invoke this action on pad #{inspect(pad)} as it has #{inspect(dir)} direction"
  end

  defp format_reason({:invalid_pad_mode, pad, mode}) do
    "Cannot invoke this action on pad #{inspect(pad)} as it works in #{inspect(mode)} mode"
  end

  defp format_reason({:invalid_demand_mode, pad, demand_mode}) do
    "Cannot invoke this action on pad #{inspect(pad)} as it uses #{inspect(demand_mode)} demand mode"
  end

  defp format_reason({:eos_sent, pad}) do
    "End of Stream has already been sent on pad #{inspect(pad)}"
  end

  defp format_reason({:invalid_caps, caps, accepted_caps}) do
    """
    Trying to send caps that do not match the specification
    Caps being sent: #{inspect(caps, pretty: true)}
    Allowed caps spec: #{inspect(accepted_caps, pretty: true)}\
    """
  end

  defp format_reason(:negative_demand) do
    "Requested demand must be positive"
  end

  defp format_reason({:invalid_event, event}) do
    "Invalid event: #{inspect(event, pretty: true)}"
  end

  defp format_reason(reason) do
    "Unknown error: #{inspect(reason, pretty: true)}"
  end
end

defmodule Membrane.LinkError do
  defexception [:message]
end

defmodule Membrane.ElementError do
  defexception [:message]
end
