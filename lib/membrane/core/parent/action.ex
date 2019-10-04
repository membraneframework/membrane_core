defmodule Membrane.Core.Parent.Action do
  @moduledoc false
  alias Membrane.{CallbackError, Clock, ParentError}
  alias Membrane.Core.{Parent, Message}

  use Bunch

  def handle_forward(element_name, message, state) do
    with {:ok, %{pid: pid}} <- state |> Parent.ChildrenModel.get_child_data(element_name) do
      send(pid, message)
      {:ok, state}
    else
      {:error, reason} ->
        {{:error, {:cannot_forward_message, [element: element_name, message: message], reason}},
         state}
    end
  end

  def handle_remove_child(children, state) do
    children = children |> Bunch.listify()

    {:ok, state} =
      if state.clock_provider.provider in children do
        %{state | clock_provider: %{clock: nil, provider: nil, choice: :auto}}
        |> choose_clock
      else
        {:ok, state}
      end

    with {:ok, data} <-
           children |> Bunch.Enum.try_map(&Parent.ChildrenModel.get_child_data(state, &1)) do
      data |> Enum.each(&Message.send(&1.pid, :prepare_shutdown))
      :ok
    end
    ~> {&1, state}
  end

  def handle_unknown_action(action, callback, module) do
    raise CallbackError, kind: :invalid_action, action: action, callback: {module, callback}
  end

  # TODO this should be in different place?
  def choose_clock(state) do
    choose_clock([], nil, state)
  end

  def choose_clock(children, provider, state) do
    cond do
      provider != nil -> get_clock_from_provider(children, provider)
      invalid_choice?(state) -> :no_provider
      true -> choose_clock_provider(children)
    end
    |> case do
      :no_provider ->
        {:ok, state}

      clock_provider ->
        Clock.proxy_for(state.clock_proxy, clock_provider.clock)
        {:ok, %{state | clock_provider: clock_provider}}
    end
  end

  defp invalid_choice?(state),
    do: state.clock_provider.clock != nil && state.clock_provider.choice == :manual

  defp get_clock_from_provider(children, provider) do
    children
    |> Enum.find(fn
      {^provider, _data} -> true
      _ -> false
    end)
    |> case do
      nil ->
        raise ParentError, "Unknown clock provider: #{inspect(provider)}"

      {^provider, %{clock: nil}} ->
        raise ParentError, "#{inspect(provider)} is not a clock provider"

      {^provider, %{clock: clock}} ->
        %{clock: clock, provider: provider, choice: :manual}
    end
  end

  defp choose_clock_provider(children) do
    case children |> Bunch.KVList.filter_by_values(& &1.clock) do
      [] ->
        %{clock: nil, provider: nil, choice: :auto}

      [{child, %{clock: clock}}] ->
        %{clock: clock, provider: child, choice: :auto}

      children ->
        raise ParentError, """
        Cannot choose clock for the pipeline, as multiple elements provide one, namely: #{
          children |> Keyword.keys() |> Enum.join(", ")
        }. Please explicitly select the clock by setting `Spec.clock_provider` parameter.
        """
    end
  end
end
