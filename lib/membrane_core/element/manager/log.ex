defmodule Membrane.Element.Manager.Log do
  alias Membrane.Element.Manager.State
  alias Membrane.Mixins.Log

  defmacro __using__(args) do
    quote location: :keep do
      use Membrane.Mixins.Log, tags: :core, import: false
      use Membrane.Mixins.Log, unquote(args |> Keyword.put(:import, false))
      unquote do
        if args |> Keyword.get(:import, true) do
          quote do: import Membrane.Element.Manager.Log
        end
      end
    end
  end

  defmacrop bring_logger do
    quote do
      use Membrane.Mixins.Log, tags: :core, import: false
    end
  end

  defmacro debug(message, state, tags \\ []) do
    quote do
      unquote bring_logger()
      Log.debug parse(unquote(message), unquote(state)), unquote(tags)
    end
  end

  @doc false
  defmacro info(message, state, tags \\ []) do
    quote do
      unquote bring_logger()
      Log.info parse(unquote(message), unquote(state)), unquote(tags)
    end
  end

  @doc false
  defmacro warn(message, state, tags \\ []) do
    quote do
      unquote bring_logger()
      Log.warn parse_warn(unquote(message), unquote(state)), unquote(tags)
    end
  end

  defmacro warn_error(message, reason, state, tags \\ []) do
    quote do
      unquote bring_logger()
      Log.warn_error parse_warn(unquote(message), unquote(state)), unquote(reason), unquote(tags)
    end
  end

  defmacro or_warn_error(v, message, state, tags \\ []) do
    quote do
      unquote bring_logger()
      Log.or_warn_error unquote(v), parse_warn(unquote(message), unquote(state)), unquote(tags)
    end
  end

  def parse(message, %State{name: name}) do
    ["Element #{name}: ", message]
  end

  def parse_warn(message, %State{name: name} = state) do
    ["Element #{name}: ", message, "\n", "state: #{inspect state}"]
  end

end
