defmodule Membrane.Core.Element.Log do
  alias Membrane.Core.Element.State
  alias Membrane.Log

  defmacro __using__(args) do
    quote location: :keep do
      use Membrane.Log, tags: :core, import: false
      use Membrane.Log, unquote(args |> Keyword.put(:import, false))

      unquote do
        if args |> Keyword.get(:import, true) do
          quote do: import(Membrane.Core.Element.Log)
        end
      end
    end
  end

  defmacrop bring_logger do
    quote do
      use Membrane.Log, tags: :core, import: false
    end
  end

  defmacro debug(message, state, tags \\ []) do
    quote do
      unquote(bring_logger())
      tags = append_tags(unquote(tags), unquote(state))
      Log.debug(parse(unquote(message), unquote(state)), tags)
    end
  end

  @doc false
  defmacro info(message, state, tags \\ []) do
    quote do
      unquote(bring_logger())
      tags = append_tags(unquote(tags), unquote(state))
      Log.info(parse(unquote(message), unquote(state)), tags)
    end
  end

  @doc false
  defmacro warn(message, state, tags \\ []) do
    quote do
      unquote(bring_logger())
      tags = append_tags(unquote(tags), unquote(state))
      Log.warn(parse_warn(unquote(message), unquote(state)), tags)
    end
  end

  defmacro warn_error(message, reason, state, tags \\ []) do
    quote do
      unquote(bring_logger())
      tags = append_tags(unquote(tags), unquote(state))
      Log.warn_error(parse_warn(unquote(message), unquote(state)), unquote(reason), tags)
      unquote({{:error, reason}, state})
    end
  end

  defmacro or_warn_error(v, message, tags \\ []) do
    use Membrane.Helper

    quote do
      with {:ok, res} <- unquote(v) |> Helper.result_with_status() do
        res
      else
        {_error, {{:error, reason}, state}} ->
          warn_error(unquote(message), reason, state, unquote(tags))
      end
    end
  end

  def parse(message, %State{name: name}) do
    ["Element #{inspect(name)}: ", message]
  end

  def parse_warn(message, %State{name: name} = state) do
    ["Element #{inspect(name)}: ", message, "\n", "state: #{inspect(state)}"]
  end

  def append_tags(tags, %State{name: name}) do
    case name do
      {name, _id} -> [name | tags]
      _ -> name
    end
  end
end
