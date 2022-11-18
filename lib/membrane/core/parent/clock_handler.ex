defmodule Membrane.Core.Parent.ClockHandler do
  @moduledoc false

  alias Membrane.{Clock, Core, ParentError}
  alias Membrane.Core.Parent.ChildEntryParser

  @spec choose_clock(
          [ChildEntryParser.raw_child_entry_t()],
          Membrane.Child.name_t() | nil,
          Core.Parent.state_t()
        ) ::
          Core.Parent.state_t() | no_return
  def choose_clock(children, provider, state) do
    %{synchronization: synchronization} = state

    components =
      case state do
        %Core.Bin.State{} -> [%{name: Membrane.Parent, clock: synchronization.parent_clock}]
        %Core.Pipeline.State{} -> []
      end

    components = components ++ children

    cond do
      provider != nil -> set_clock_provider(get_clock_from_provider(components, provider), state)
      synchronization.clock_provider.choice == :manual -> state
      true -> choose_clock_provider(components) |> set_clock_provider(state)
    end
  end

  @spec reset_clock(Core.Parent.state_t()) :: Core.Parent.state_t()
  def reset_clock(state),
    do: set_clock_provider(%{clock: nil, provider: nil, choice: :auto}, state)

  defp set_clock_provider(clock_provider, state) do
    Clock.proxy_for(state.synchronization.clock_proxy, clock_provider.clock)
    put_in(state, [:synchronization, :clock_provider], clock_provider)
  end

  defp get_clock_from_provider(components, provider) do
    components
    |> Enum.find(&(&1.name == provider))
    |> case do
      nil ->
        raise ParentError, "Unknown clock provider: #{inspect(provider)}"

      %{clock: nil} ->
        raise ParentError, "#{inspect(provider)} is not a clock provider"

      %{clock: clock} ->
        %{clock: clock, provider: provider, choice: :manual}
    end
  end

  defp choose_clock_provider(components) do
    case components |> Enum.filter(& &1.clock) do
      [] ->
        %{clock: nil, provider: nil, choice: :auto}

      [%{name: name, clock: clock}] ->
        %{clock: clock, provider: name, choice: :auto}

      components ->
        raise ParentError, """
        Cannot choose clock for the parent, as multiple components provide one, namely: #{Enum.map_join(components, ", ", & &1.name)}. Please explicitly select the clock by setting `ChildrenSpec.clock_provider` parameter.
        """
    end
  end
end
