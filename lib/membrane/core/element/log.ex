defmodule Membrane.Core.Element.Log do
  @moduledoc false
  alias Membrane.Core.Element.State
  alias Membrane.Log
  alias Membrane.Log.Logger

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

  defmacro debug(message, state, tags \\ []) do
    tags =
      quote do
        unquote(__MODULE__).append_tags(unquote(tags), unquote(state))
      end

    quote do
      unquote(bring_logger())
      Log.debug(unquote(__MODULE__).parse(unquote(message), unquote(state)), unquote(tags))
    end
  end

  @doc false
  defmacro info(message, state, tags \\ []) do
    tags =
      quote do
        unquote(__MODULE__).append_tags(unquote(tags), unquote(state))
      end

    quote do
      unquote(bring_logger())
      Log.info(unquote(__MODULE__).parse(unquote(message), unquote(state)), unquote(tags))
    end
  end

  @doc false
  defmacro warn(message, state, tags \\ []) do
    tags =
      quote do
        unquote(__MODULE__).append_tags(unquote(tags), unquote(state))
      end

    quote do
      unquote(bring_logger())
      Log.warn(unquote(__MODULE__).parse_warn(unquote(message), unquote(state)), unquote(tags))
    end
  end

  defmacro warn_error(message, reason, state, tags \\ []) do
    tags =
      quote do
        unquote(__MODULE__).append_tags(unquote(tags), unquote(state))
      end

    quote do
      unquote(bring_logger())

      Log.warn_error(
        unquote(__MODULE__).parse_warn(unquote(message), unquote(state)),
        unquote(reason),
        unquote(tags)
      )

      unquote({{:error, reason}, state})
    end
  end

  defmacro or_warn_error(v, message, tags \\ []) do
    use Bunch

    quote do
      with {:ok, res} <- unquote(v) |> Bunch.stateful_try_with_status() do
        res
      else
        {_error, {{:error, reason}, state}} ->
          unquote(__MODULE__).warn_error(unquote(message), reason, state, unquote(tags))
      end
    end
  end

  @spec parse(Logger.message_t(), State.t()) :: Logger.message_t()
  def parse(message, %State{name: name}) do
    ["Element #{inspect(name)}: ", message]
  end

  def parse_warn(message, %State{name: name} = state) do
    ["Element #{inspect(name)}: ", message, "\n", "state: #{inspect(state)}"]
  end

  @spec append_tags([Logger.tag_t()], State.t()) :: State.t()
  def append_tags(tags, %State{name: name}) do
    case name do
      {name, _id} -> [name | tags]
      _ -> name
    end
  end

  defp bring_logger do
    quote do
      use Membrane.Log, tags: :core, import: false
    end
  end
end
