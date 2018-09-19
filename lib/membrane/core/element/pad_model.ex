defmodule Membrane.Core.Element.PadModel do
  @moduledoc false
  # Utility functions for veryfying and manipulating pads and their data.

  alias Membrane.Element.Pad
  alias Membrane.Core.Element.State
  alias Membrane.Core.PullBuffer
  use Bunch

  @type pad_data_t :: %{
          required(:accepted_caps) => any,
          required(:availability) => Pad.availability_t(),
          required(:direction) => Pad.direction_t(),
          required(:mode) => Pad.mode_t(),
          required(:name) => Pad.name_t(),
          required(:options) => %{
            optional(:demand_in) => Membrane.Buffer.Metric.unit_t(),
            optional(:other_demand_in) => Membrane.Buffer.Metric.unit_t()
          },
          optional(:current_id) => non_neg_integer,
          required(:pid) => pid,
          required(:other_ref) => Pad.ref_t(),
          required(:caps) => Membrane.Caps.t(),
          required(:sos) => boolean(),
          required(:eos) => boolean(),
          optional(:sticky_messages) => [Membrane.Event.t()],
          optional(:buffer) => PullBuffer.t(),
          optional(:demand) => integer()
        }

  @type pads_data_t :: %{Pad.ref_t() => pad_data_t}

  @type pad_info_t :: %{
          required(:accepted_caps) => any,
          required(:availability) => Pad.availability_t(),
          required(:direction) => Pad.direction_t(),
          required(:mode) => Pad.mode_t(),
          required(:name) => Pad.name_t(),
          required(:options) => %{
            optional(:demand_in) => Membrane.Buffer.Metric.unit_t(),
            optional(:other_demand_in) => Membrane.Buffer.Metric.unit_t()
          },
          optional(:current_id) => non_neg_integer
        }

  @type pads_info_t :: %{Pad.name_t() => pad_info_t}

  @type pads_t :: %{
          data: pads_data_t,
          info: pads_info_t,
          dynamic_currently_linking: [Pad.ref_t()]
        }

  @type unknown_pad_error_t :: {:error, {:unknown_pad, Pad.name_t()}}

  @spec assert_instance(Pad.ref_t(), State.t()) :: :ok | unknown_pad_error_t
  def assert_instance(pad_ref, state) do
    if state.pads.data |> Map.has_key?(pad_ref) do
      :ok
    else
      {:error, {:unknown_pad, pad_ref}}
    end
  end

  @spec assert_instance!(Pad.ref_t(), State.t()) :: :ok
  def assert_instance!(pad_ref, state) do
    :ok = assert_instance(pad_ref, state)
  end

  defmacro assert_data(pad_ref, pattern, state) do
    quote do
      with {:ok, data} <- unquote(__MODULE__).get_data(unquote(pad_ref), unquote(state)) do
        if match?(unquote(pattern), data) do
          :ok
        else
          {:error,
           {:invalid_pad_data, ref: unquote(pad_ref), pattern: unquote(pattern), data: data}}
        end
      end
    end
  end

  defmacro assert_data!(pad_ref, pattern, state) do
    quote do
      :ok = unquote(__MODULE__).assert_data(unquote(pad_ref), unquote(pattern), unquote(state))
    end
  end

  @spec filter_refs_by_data(constraints :: map, State.t()) :: [Pad.ref_t()]
  def filter_refs_by_data(constraints \\ %{}, state)

  def filter_refs_by_data(constraints, state) when constraints == %{} do
    state.pads.data |> Map.keys()
  end

  def filter_refs_by_data(constraints, state) do
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

  @spec get_data(Pad.ref_t(), keys :: atom | [atom], State.t()) ::
          {:ok, pad_data_t | any} | unknown_pad_error_t
  def get_data(pad_ref, keys \\ [], state) do
    with :ok <- assert_instance(pad_ref, state) do
      state
      |> Bunch.Struct.get_in(data_keys(pad_ref, keys))
      ~> {:ok, &1}
    end
  end

  @spec get_data!(Pad.ref_t(), keys :: atom | [atom], State.t()) :: pad_data_t | any
  def get_data!(pad_ref, keys \\ [], state) do
    {:ok, pad_data} = get_data(pad_ref, keys, state)
    pad_data
  end

  @spec set_data(Pad.ref_t(), keys :: atom | [atom], State.t()) ::
          State.stateful_t(:ok | unknown_pad_error_t)
  def set_data(pad_ref, keys \\ [], v, state) do
    with {:ok, state} <- {assert_instance(pad_ref, state), state} do
      state
      |> Bunch.Struct.put_in(data_keys(pad_ref, keys), v)
      ~> {:ok, &1}
    end
  end

  @spec set_data!(Pad.ref_t(), keys :: atom | [atom], State.t()) ::
          State.stateful_t(:ok | unknown_pad_error_t)
  def set_data!(pad_ref, keys \\ [], v, state) do
    {:ok, state} = set_data(pad_ref, keys, v, state)
    state
  end

  @spec update_data(Pad.ref_t(), keys :: atom | [atom], (data -> {:ok | error, data}), State.t()) ::
          State.stateful_t(:ok | error | unknown_pad_error_t)
        when data: pad_data_t | any, error: {:error, reason :: any}
  def update_data(pad_ref, keys \\ [], f, state) do
    with {:ok, state} <- {assert_instance(pad_ref, state), state},
         {:ok, state} <-
           state
           |> Bunch.Struct.get_and_update_in(data_keys(pad_ref, keys), f) do
      {:ok, state}
    else
      {{:error, reason}, state} -> {{:error, reason}, state}
    end
  end

  @spec update_data!(Pad.ref_t(), keys :: atom | [atom], (data -> data), State.t()) :: State.t()
        when data: pad_data_t | any
  def update_data!(pad_ref, keys \\ [], f, state) do
    :ok = assert_instance(pad_ref, state)

    state
    |> Bunch.Struct.update_in(data_keys(pad_ref, keys), f)
  end

  @spec get_and_update_data(
          Pad.ref_t(),
          keys :: atom | [atom],
          (data -> {success | error, data}),
          State.t()
        ) :: State.stateful_t(success | error | unknown_pad_error_t)
        when data: pad_data_t | any, success: {:ok, data}, error: {:error, reason :: any}
  def get_and_update_data(pad_ref, keys \\ [], f, state) do
    with {:ok, state} <- {assert_instance(pad_ref, state), state},
         {{:ok, out}, state} <-
           state
           |> Bunch.Struct.get_and_update_in(data_keys(pad_ref, keys), f) do
      {{:ok, out}, state}
    else
      {{:error, reason}, state} -> {{:error, reason}, state}
    end
  end

  @spec get_and_update_data!(
          Pad.ref_t(),
          keys :: atom | [atom],
          (data -> {data, data}),
          State.t()
        ) :: State.stateful_t(data)
        when data: pad_data_t | any
  def get_and_update_data!(pad_ref, keys \\ [], f, state) do
    :ok = assert_instance(pad_ref, state)

    state
    |> Bunch.Struct.get_and_update_in(data_keys(pad_ref, keys), f)
  end

  @spec pop_data(Pad.ref_t(), State.t()) ::
          State.stateful_t({:ok, pad_data_t | any} | unknown_pad_error_t)
  def pop_data(pad_ref, state) do
    with {:ok, state} <- {assert_instance(pad_ref, state), state} do
      state
      |> Bunch.Struct.pop_in(data_keys(pad_ref))
      ~> {:ok, &1}
    end
  end

  @spec pop_data!(Pad.ref_t(), State.t()) :: State.stateful_t(pad_data_t | any)
  def pop_data!(pad_ref, state) do
    {{:ok, pad_data}, state} = pop_data(pad_ref, state)
    {pad_data, state}
  end

  @spec delete_data(Pad.ref_t(), State.t()) :: State.stateful_t(:ok | unknown_pad_error_t)
  def delete_data(pad_ref, state) do
    with {:ok, {_out, state}} <- pop_data(pad_ref, state) do
      {:ok, state}
    end
  end

  @spec delete_data!(Pad.ref_t(), State.t()) :: State.t()
  def delete_data!(pad_ref, state) do
    {:ok, state} = delete_data(pad_ref, state)
    state
  end

  @spec constraints_met?(pad_data_t, map) :: boolean
  defp constraints_met?(data, constraints) do
    constraints |> Enum.all?(fn {k, v} -> data[k] === v end)
  end

  @spec data_keys(Pad.ref_t(), keys :: atom | [atom]) :: [atom]
  defp data_keys(pad_ref, keys \\ []) do
    [:pads, :data, pad_ref | Bunch.listify(keys)]
  end
end
