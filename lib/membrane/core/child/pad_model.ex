defmodule Membrane.Core.Child.PadModel do
  @moduledoc false

  # Utility functions for veryfying and manipulating pads and their data.

  use Bunch

  alias Bunch.Type
  alias Membrane.Core.Child
  alias Membrane.Pad

  @type pads_data_t :: %{Pad.ref_t() => Pad.Data.t()}

  @type pad_info_t :: %{
          required(:accepted_caps) => any,
          required(:availability) => Pad.availability_t(),
          required(:direction) => Pad.direction_t(),
          required(:mode) => Pad.mode_t(),
          required(:name) => Pad.name_t(),
          optional(:demand_unit) => Membrane.Buffer.Metric.unit_t(),
          optional(:other_demand_unit) => Membrane.Buffer.Metric.unit_t()
        }

  @type pads_info_t :: %{Pad.name_t() => pad_info_t}

  @type pads_t :: %{
          data: pads_data_t,
          info: pads_info_t,
          dynamic_currently_linking: [Pad.ref_t()]
        }

  @type unknown_pad_error_t :: {:error, {:unknown_pad, Pad.name_t()}}

  @spec assert_instance(Child.state_t(), Pad.ref_t()) ::
          :ok | unknown_pad_error_t
  def assert_instance(%{pads: %{data: data}}, pad_ref) when is_map_key(data, pad_ref), do: :ok
  def assert_instance(_state, pad_ref), do: {:error, {:unknown_pad, pad_ref}}

  @spec assert_instance!(Child.state_t(), Pad.ref_t()) :: :ok
  def assert_instance!(state, pad_ref) do
    :ok = assert_instance(state, pad_ref)
  end

  defmacro assert_data(state, pad_ref, pattern) do
    quote do
      with {:ok, data} <- unquote(__MODULE__).get_data(unquote(state), unquote(pad_ref)) do
        if match?(unquote(pattern), data) do
          :ok
        else
          {:error,
           {:invalid_pad_data, ref: unquote(pad_ref), pattern: unquote(pattern), data: data}}
        end
      end
    end
  end

  defmacro assert_data!(state, pad_ref, pattern) do
    quote do
      :ok = unquote(__MODULE__).assert_data(unquote(state), unquote(pad_ref), unquote(pattern))
    end
  end

  @spec filter_refs_by_data(Child.state_t(), constraints :: map) :: [Pad.ref_t()]
  def filter_refs_by_data(state, constraints \\ %{})

  def filter_refs_by_data(state, constraints) when constraints == %{} do
    state.pads.data |> Map.keys()
  end

  def filter_refs_by_data(state, constraints) do
    state.pads.data
    |> Enum.filter(fn {_name, data} -> data |> constraints_met?(constraints) end)
    |> Keyword.keys()
  end

  @spec filter_data(Child.state_t(), constraints :: map) :: %{atom => Pad.Data.t()}
  def filter_data(state, constraints \\ %{})

  def filter_data(state, constraints) when constraints == %{} do
    state.pads.data
  end

  def filter_data(state, constraints) do
    state.pads.data
    |> Enum.filter(fn {_name, data} -> data |> constraints_met?(constraints) end)
    |> Map.new()
  end

  @spec get_data(Child.state_t(), Pad.ref_t()) :: {:ok, Pad.Data.t() | any} | unknown_pad_error_t
  def get_data(%{pads: %{data: data}}, pad_ref)
      when is_map_key(data, pad_ref) do
    data
    |> Map.get(pad_ref)
    ~> {:ok, &1}
  end

  def get_data(_state, pad_ref), do: {:error, {:unknown_pad, pad_ref}}

  @spec get_data(Child.state_t(), Pad.ref_t(), keys :: atom | [atom]) ::
          {:ok, Pad.Data.t() | any} | unknown_pad_error_t
  def get_data(%{pads: %{data: data}}, pad_ref, keys)
      when is_map_key(data, pad_ref) and is_list(keys) do
    data
    |> get_in([pad_ref | keys])
    ~> {:ok, &1}
  end

  def get_data(%{pads: %{data: data}}, pad_ref, key)
      when is_map_key(data, pad_ref) and is_atom(key) do
    data
    |> get_in([pad_ref, key])
    ~> {:ok, &1}
  end

  def get_data(_state, pad_ref, _keys), do: {:error, {:unknown_pad, pad_ref}}

  @spec get_data!(Child.state_t(), Pad.ref_t()) :: Pad.Data.t() | any
  def get_data!(state, pad_ref) do
    {:ok, pad_data} = get_data(state, pad_ref)
    pad_data
  end

  @spec get_data!(Child.state_t(), Pad.ref_t(), keys :: atom | [atom]) :: Pad.Data.t() | any
  def get_data!(state, pad_ref, keys) do
    {:ok, pad_data} = get_data(state, pad_ref, keys)
    pad_data
  end

  @spec set_data(Child.state_t(), Pad.ref_t(), keys :: atom | [atom], value :: term()) ::
          Type.stateful_t(:ok | unknown_pad_error_t, Child.state_t())
  def set_data(state, pad_ref, keys \\ [], value) do
    case assert_instance(state, pad_ref) do
      :ok ->
        put_in(state, data_keys(pad_ref, keys), value)
        ~> {:ok, &1}

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  @spec set_data!(Child.state_t(), Pad.ref_t(), keys :: atom | [atom], value :: term()) ::
          Child.state_t()
  def set_data!(state, pad_ref, keys \\ [], value) do
    {:ok, state} = set_data(state, pad_ref, keys, value)
    state
  end

  @spec update_data(
          Child.state_t(),
          Pad.ref_t(),
          keys :: atom | [atom],
          (data -> {:ok | error, data})
        ) ::
          Type.stateful_t(:ok | error | unknown_pad_error_t, Child.state_t())
        when data: Pad.Data.t() | any, error: {:error, reason :: any}
  def update_data(state, pad_ref, keys \\ [], f) do
    case assert_instance(state, pad_ref) do
      :ok ->
        state |> Bunch.Access.get_and_update_in(data_keys(pad_ref, keys), f)

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  @spec update_data!(Child.state_t(), Pad.ref_t(), keys :: atom | [atom], (data -> data)) ::
          Child.state_t()
        when data: Pad.Data.t() | any
  def update_data!(state, pad_ref, keys \\ [], f) do
    :ok = assert_instance(state, pad_ref)

    state
    |> Bunch.Access.update_in(data_keys(pad_ref, keys), f)
  end

  @spec update_multi(Child.state_t(), Pad.ref_t(), [
          {key :: atom, (data -> data)} | {key :: atom, any}
        ]) ::
          Type.stateful_t(:ok | unknown_pad_error_t, Child.state_t())
        when data: Pad.Data.t() | any
  def update_multi(state, pad_ref, updates) do
    case assert_instance(state, pad_ref) do
      :ok ->
        state
        |> Bunch.Access.update_in([:pads, :data, pad_ref], fn pad_data ->
          apply_updates(pad_data, updates)
        end)
        ~> {:ok, &1}

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  @spec update_multi!(Child.state_t(), Pad.ref_t(), [
          {key :: atom, (data -> data)} | {key :: atom, any}
        ]) ::
          Child.state_t()
        when data: Pad.Data.t() | any
  def update_multi!(state, pad_ref, updates) do
    {:ok, state} = update_multi(state, pad_ref, updates)
    state
  end

  @spec get_and_update_data(
          Child.state_t(),
          Pad.ref_t(),
          keys :: atom | [atom],
          (data -> {success | error, data})
        ) :: Type.stateful_t(success | error | unknown_pad_error_t, Child.state_t())
        when data: Pad.Data.t() | any, success: {:ok, data}, error: {:error, reason :: any}
  def get_and_update_data(state, pad_ref, keys \\ [], f) do
    case assert_instance(state, pad_ref) do
      :ok ->
        state
        |> Bunch.Access.get_and_update_in(data_keys(pad_ref, keys), f)

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  @spec get_and_update_data!(
          Child.state_t(),
          Pad.ref_t(),
          keys :: atom | [atom],
          (data -> {data, data})
        ) :: Type.stateful_t(data, Child.state_t())
        when data: Pad.Data.t() | any
  def get_and_update_data!(state, pad_ref, keys \\ [], f) do
    :ok = assert_instance(state, pad_ref)

    state
    |> Bunch.Access.get_and_update_in(data_keys(pad_ref, keys), f)
  end

  @spec pop_data(Child.state_t(), Pad.ref_t()) ::
          Type.stateful_t({:ok, Pad.Data.t()} | unknown_pad_error_t, Child.state_t())
  def pop_data(state, pad_ref) do
    with :ok <- assert_instance(state, pad_ref) do
      {data, state} =
        state
        |> Bunch.Access.pop_in(data_keys(pad_ref))

      {{:ok, data}, state}
    end
  end

  @spec pop_data!(Child.state_t(), Pad.ref_t()) :: Type.stateful_t(Pad.Data.t(), Child.state_t())
  def pop_data!(state, pad_ref) do
    {{:ok, pad_data}, state} = pop_data(state, pad_ref)
    {pad_data, state}
  end

  @spec delete_data(Child.state_t(), Pad.ref_t()) ::
          Type.stateful_t(:ok | unknown_pad_error_t, Child.state_t())
  def delete_data(state, pad_ref) do
    with {{:ok, _out}, state} <- pop_data(state, pad_ref) do
      {:ok, state}
    end
  end

  @spec delete_data!(Child.state_t(), Pad.ref_t()) :: Child.state_t()
  def delete_data!(state, pad_ref) do
    {:ok, state} = delete_data(state, pad_ref)
    state
  end

  @spec apply_updates(Pad.Data.t(), [{key :: atom, (data -> data)} | {key :: atom, any}]) ::
          Pad.Data.t()
        when data: Pad.Data.t()
  defp apply_updates(pad_data, updates) do
    for {key, update} <- updates, reduce: pad_data do
      pad_data ->
        case update do
          f when is_function(f) ->
            Map.update(pad_data, key, nil, f)

          value ->
            Map.put(pad_data, key, value)
        end
    end
  end

  @spec constraints_met?(Pad.Data.t(), map) :: boolean
  defp constraints_met?(data, constraints) do
    constraints |> Enum.all?(fn {k, v} -> data[k] === v end)
  end

  @spec data_keys(Pad.ref_t()) :: [atom]
  defp data_keys(pad_ref), do: [:pads, :data, pad_ref]

  @spec data_keys(Pad.ref_t(), keys :: atom | [atom]) :: [atom]
  @compile {:inline, data_keys: 2}
  defp data_keys(pad_ref, keys)

  defp data_keys(pad_ref, keys) when is_list(keys) do
    [:pads, :data, pad_ref | keys]
  end

  defp data_keys(pad_ref, key) do
    [:pads, :data, pad_ref, key]
  end
end
