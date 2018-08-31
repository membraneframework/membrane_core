defmodule Membrane.Core.Element.PadModel do
  @moduledoc false
  # Utility functions for veryfying and manipulating pads and their data.

  alias Membrane.Element.Pad
  alias Membrane.Core.Element.State
  use Bunch

  @type pad_data_t :: map
  @type pad_info_t :: map
  @type pads_t :: %{data: pad_data_t, info: pad_info_t, dynamic_currently_linking: [Pad.name_t()]}

  @type unknown_pad_error_t :: {:error, {:unknown_pad, Pad.name_t()}}

  @spec assert_instance(Pad.name_t(), State.t()) :: :ok | unknown_pad_error_t
  def assert_instance(pad_name, state) do
    if state.pads.data |> Map.has_key?(pad_name) do
      :ok
    else
      {:error, {:unknown_pad, pad_name}}
    end
  end

  @spec assert_instance!(Pad.name_t(), State.t()) :: :ok
  def assert_instance!(pad_name, state) do
    :ok = assert_instance(pad_name, state)
  end

  defmacro assert_data(pad_name, pattern, state) do
    quote do
      with {:ok, data} <- unquote(__MODULE__).get_data(unquote(pad_name), unquote(state)) do
        if match?(unquote(pattern), data) do
          :ok
        else
          {:error,
           {:invalid_pad_data, name: unquote(pad_name), pattern: unquote(pattern), data: data}}
        end
      end
    end
  end

  defmacro assert_data!(pad_name, pattern, state) do
    quote do
      :ok = unquote(__MODULE__).assert_data(unquote(pad_name), unquote(pattern), unquote(state))
    end
  end

  @spec filter_names_by_data(constraints :: map, State.t()) :: [Pad.name_t()]
  def filter_names_by_data(constraints \\ %{}, state)

  def filter_names_by_data(constraints, state) when constraints == %{} do
    state.pads.data |> Map.keys()
  end

  def filter_names_by_data(constraints, state) do
    state.pads.data
    |> Enum.filter(fn {_name, data} -> data |> constraints_met?(constraints) end)
    |> Keyword.keys()
  end

  @spec filter_data(constraints :: map, State.t()) :: %{atom => pad_data_t}
  def filter_data(constraints \\ %{}, state)

  def filter_data(constraints, state) when constraints == %{} do
    state.pads.data
  end

  def filter_data(constraints, state) do
    state.pads.data
    |> Enum.filter(fn {_name, data} -> data |> constraints_met?(constraints) end)
    |> Map.new()
  end

  @spec get_data(Pad.name_t(), keys :: atom | [atom], State.t()) ::
          {:ok, pad_data_t | any} | unknown_pad_error_t
  def get_data(pad_name, keys \\ [], state) do
    with :ok <- assert_instance(pad_name, state) do
      state
      |> Bunch.Struct.get_in(data_keys(pad_name, keys))
      ~> {:ok, &1}
    end
  end

  @spec get_data!(Pad.name_t(), keys :: atom | [atom], State.t()) :: pad_data_t | any
  def get_data!(pad_name, keys \\ [], state) do
    {:ok, pad_data} = get_data(pad_name, keys, state)
    pad_data
  end

  @spec set_data(Pad.name_t(), keys :: atom | [atom], State.t()) ::
          State.stateful_t(:ok | unknown_pad_error_t)
  def set_data(pad_name, keys \\ [], v, state) do
    with {:ok, state} <- {assert_instance(pad_name, state), state} do
      state
      |> Bunch.Struct.put_in(data_keys(pad_name, keys), v)
      ~> {:ok, &1}
    end
  end

  @spec set_data!(Pad.name_t(), keys :: atom | [atom], State.t()) ::
          State.stateful_t(:ok | unknown_pad_error_t)
  def set_data!(pad_name, keys \\ [], v, state) do
    {:ok, state} = set_data(pad_name, keys, v, state)
    state
  end

  @spec update_data(Pad.name_t(), keys :: atom | [atom], (data -> {:ok | error, data}), State.t()) ::
          State.stateful_t(:ok | error | unknown_pad_error_t)
        when data: pad_data_t | any, error: {:error, reason :: any}
  def update_data(pad_name, keys \\ [], f, state) do
    with {:ok, state} <- {assert_instance(pad_name, state), state},
         {:ok, state} <-
           state
           |> Bunch.Struct.get_and_update_in(data_keys(pad_name, keys), f) do
      {:ok, state}
    else
      {{:error, reason}, state} -> {{:error, reason}, state}
    end
  end

  @spec update_data!(Pad.name_t(), keys :: atom | [atom], (data -> data), State.t()) :: State.t()
        when data: pad_data_t | any
  def update_data!(pad_name, keys \\ [], f, state) do
    :ok = assert_instance(pad_name, state)

    state
    |> Bunch.Struct.update_in(data_keys(pad_name, keys), f)
  end

  @spec get_and_update_data(
          Pad.name_t(),
          keys :: atom | [atom],
          (data -> {success | error, data}),
          State.t()
        ) :: State.stateful_t(success | error | unknown_pad_error_t)
        when data: pad_data_t | any, success: {:ok, data}, error: {:error, reason :: any}
  def get_and_update_data(pad_name, keys \\ [], f, state) do
    with {:ok, state} <- {assert_instance(pad_name, state), state},
         {{:ok, out}, state} <-
           state
           |> Bunch.Struct.get_and_update_in(data_keys(pad_name, keys), f) do
      {{:ok, out}, state}
    else
      {{:error, reason}, state} -> {{:error, reason}, state}
    end
  end

  @spec get_and_update_data!(
          Pad.name_t(),
          keys :: atom | [atom],
          (data -> {data, data}),
          State.t()
        ) :: State.stateful_t(data)
        when data: pad_data_t | any
  def get_and_update_data!(pad_name, keys \\ [], f, state) do
    :ok = assert_instance(pad_name, state)

    state
    |> Bunch.Struct.get_and_update_in(data_keys(pad_name, keys), f)
  end

  @spec pop_data(Pad.name_t(), State.t()) ::
          State.stateful_t({:ok, pad_data_t | any} | unknown_pad_error_t)
  def pop_data(pad_name, state) do
    with {:ok, state} <- {assert_instance(pad_name, state), state} do
      state
      |> Bunch.Struct.pop_in(data_keys(pad_name))
      ~> {:ok, &1}
    end
  end

  @spec pop_data!(Pad.name_t(), State.t()) :: State.stateful_t(pad_data_t | any)
  def pop_data!(pad_name, state) do
    {{:ok, pad_data}, state} = pop_data(pad_name, state)
    {pad_data, state}
  end

  @spec delete_data(Pad.name_t(), State.t()) :: State.stateful_t(:ok | unknown_pad_error_t)
  def delete_data(pad_name, state) do
    with {:ok, {_out, state}} <- pop_data(pad_name, state) do
      {:ok, state}
    end
  end

  @spec delete_data!(Pad.name_t(), State.t()) :: State.t()
  def delete_data!(pad_name, state) do
    {:ok, state} = delete_data(pad_name, state)
    state
  end

  @spec constraints_met?(pad_data_t, map) :: boolean
  defp constraints_met?(data, constraints) do
    constraints |> Enum.all?(fn {k, v} -> data[k] === v end)
  end

  @spec data_keys(Pad.name_t(), keys :: atom | [atom]) :: [atom]
  defp data_keys(pad_name, keys \\ []) do
    [:pads, :data, pad_name | Bunch.listify(keys)]
  end
end
