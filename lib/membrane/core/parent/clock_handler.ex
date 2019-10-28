defmodule Membrane.Core.Parent.ClockHandler do
  @moduledoc false

  alias Membrane.{Clock, ParentError}
  alias Membrane.Core.Parent
  alias Membrane.Core.Parent.State

  @spec choose_clock(State.t()) :: {:ok, State.t()}
  def choose_clock(state) do
    choose_clock([], nil, state)
  end

  @spec choose_clock([Parent.Child.t()], Membrane.Child.name_t() | nil, State.t()) ::
          {:ok, State.t()} | no_return
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
    |> Enum.find(&(&1.name == provider))
    |> case do
      nil ->
        raise ParentError, "Unknown clock provider: #{inspect(provider)}"

      %Parent.Child{clock: nil} ->
        raise ParentError, "#{inspect(provider)} is not a clock provider"

      %Parent.Child{clock: clock} ->
        %{clock: clock, provider: provider, choice: :manual}
    end
  end

  defp choose_clock_provider(children) do
    case children |> Enum.filter(& &1.clock) do
      [] ->
        %{clock: nil, provider: nil, choice: :auto}

      [%Parent.Child{name: name, clock: clock}] ->
        %{clock: clock, provider: name, choice: :auto}

      children ->
        raise ParentError, """
        Cannot choose clock for the pipeline, as multiple elements provide one, namely: #{
          children |> Enum.map(& &1.name) |> Enum.join(", ")
        }. Please explicitly select the clock by setting `ParentSpec.clock_provider` parameter.
        """
    end
  end
end
