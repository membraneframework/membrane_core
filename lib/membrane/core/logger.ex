defmodule Membrane.Core.Logger do
  @moduledoc false

  def put_pipeline_prefix() do
    put_prefix("pipeline@#{:erlang.pid_to_list(self())}")
  end

  def put_bin_prefix(name) do
    name_str = if String.valid?(name), do: name, else: inspect(name)
    put_prefix(name_str <> " bin")
  end

  def put_element_prefix(name) do
    name_str = if String.valid?(name), do: name, else: inspect(name)
    put_prefix(name_str)
  end

  defp put_prefix(prefix) do
    Logger.metadata(mb: prefix)

    if Membrane.Logger.get_config(:prefix, true) do
      Process.put(:membrane_logger_prefix, "(" <> prefix <> ") ")
    end

    :ok
  end
end
