defmodule Membrane.Core.Child.PadModel do
  @moduledoc false

  # Utility functions for veryfying and manipulating pads and their data.

  use Bunch

  alias Bunch.Type
  alias Membrane.Core.Child
  alias Membrane.Pad

  @type bin_pad_data_t :: %Membrane.Bin.PadData{
          ref: Membrane.Pad.ref_t(),
          options: Membrane.ParentSpec.pad_options_t(),
          link_id: Membrane.Core.Parent.ChildLifeController.LinkHandler.link_id_t(),
          endpoint: Membrane.Core.Parent.Link.Endpoint.t(),
          linked?: boolean(),
          response_received?: boolean(),
          spec_ref: Membrane.Core.Parent.ChildLifeController.spec_ref_t(),
          accepted_caps: Membrane.Caps.Matcher.caps_specs_t(),
          availability: Pad.availability_t(),
          direction: Pad.direction_t(),
          mode: Pad.mode_t(),
          name: Pad.name_t(),
          demand_unit: Membrane.Buffer.Metric.unit_t() | nil
        }

  @type element_pad_data_t :: %Membrane.Element.PadData{
          accepted_caps: Membrane.Caps.Matcher.caps_specs_t(),
          availability: Pad.availability_t(),
          caps: Membrane.Caps.t() | nil,
          demand: integer() | nil,
          start_of_stream?: boolean(),
          end_of_stream?: boolean(),
          direction: Pad.direction_t(),
          mode: Pad.mode_t(),
          name: Pad.name_t(),
          ref: Pad.ref_t(),
          demand_unit: Membrane.Buffer.Metric.unit_t() | nil,
          other_demand_unit: Membrane.Buffer.Metric.unit_t() | nil,
          pid: pid,
          other_ref: Pad.ref_t(),
          sticky_messages: [Membrane.Event.t()],
          input_queue: Membrane.Core.Element.InputQueue.t() | nil,
          options: %{optional(atom) => any},
          toilet: Membrane.Core.Element.Toilet.t() | nil,
          demand_mode: :auto | :manual | nil,
          auto_demand_size: pos_integer() | nil,
          associated_pads: [Pad.ref_t()] | nil
        }

  @type pad_data_t :: bin_pad_data_t | element_pad_data_t

  @type pads_data_t :: %{Pad.ref_t() => pad_data_t}

  @type pad_info_t :: %{
          required(:accepted_caps) => any,
          required(:availability) => Pad.availability_t(),
          required(:direction) => Pad.direction_t(),
          required(:mode) => Pad.mode_t(),
          required(:name) => Pad.name_t(),
          optional(:demand_unit) => Membrane.Buffer.Metric.unit_t(),
          optional(:other_demand_unit) => Membrane.Buffer.Metric.unit_t(),
          optional(:demand_mode) => :auto | :manual
        }

  @type pads_info_t :: %{Pad.name_t() => pad_info_t}

  @type pads_t :: %{
          data: pads_data_t,
          info: pads_info_t
        }

  @type unknown_pad_error_t :: {:error, {:unknown_pad, Pad.name_t()}}

  @spec assert_instance(Child.state_t(), Pad.ref_t()) ::
          :ok | unknown_pad_error_t
  def assert_instance(state, pad_ref) do
    if state.pads.data |> Map.has_key?(pad_ref) do
      :ok
    else
      {:error, {:unknown_pad, pad_ref}}
    end
  end

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

  @spec filter_data(Child.state_t(), constraints :: map) :: %{atom => pad_data_t}
  def filter_data(state, constraints \\ %{})

  def filter_data(state, constraints) when constraints == %{} do
    state.pads.data
  end

  def filter_data(state, constraints) do
    state.pads.data
    |> Enum.filter(fn {_name, data} -> data |> constraints_met?(constraints) end)
    |> Map.new()
  end

  @spec get_data(Child.state_t(), Pad.ref_t(), keys :: atom | [atom]) ::
          {:ok, pad_data_t | any} | unknown_pad_error_t
  def get_data(state, pad_ref, keys \\ []) do
    with :ok <- assert_instance(state, pad_ref) do
      state
      |> Bunch.Access.get_in(data_keys(pad_ref, keys))
      ~> {:ok, &1}
    end
  end

  @spec get_data!(Child.state_t(), Pad.ref_t(), keys :: atom | [atom]) :: pad_data_t | any
  def get_data!(state, pad_ref, keys \\ []) do
    {:ok, pad_data} = get_data(state, pad_ref, keys)
    pad_data
  end

  @spec set_data(Child.state_t(), Pad.ref_t(), keys :: atom | [atom], value :: term()) ::
          Type.stateful_t(:ok | unknown_pad_error_t, Child.state_t())
  def set_data(state, pad_ref, keys \\ [], value) do
    with {:ok, state} <- {assert_instance(state, pad_ref), state} do
      state
      |> Bunch.Access.put_in(data_keys(pad_ref, keys), value)
      ~> {:ok, &1}
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
        when data: pad_data_t | any, error: {:error, reason :: any}
  def update_data(state, pad_ref, keys \\ [], f) do
    with {:ok, state} <- {assert_instance(state, pad_ref), state},
         {:ok, state} <-
           state
           |> Bunch.Access.get_and_update_in(data_keys(pad_ref, keys), f) do
      {:ok, state}
    else
      {{:error, reason}, state} -> {{:error, reason}, state}
    end
  end

  @spec update_data!(Child.state_t(), Pad.ref_t(), keys :: atom | [atom], (data -> data)) ::
          Child.state_t()
        when data: pad_data_t | any
  def update_data!(state, pad_ref, keys \\ [], f) do
    :ok = assert_instance(state, pad_ref)

    state
    |> Bunch.Access.update_in(data_keys(pad_ref, keys), f)
  end

  @spec get_and_update_data(
          Child.state_t(),
          Pad.ref_t(),
          keys :: atom | [atom],
          (data -> {success | error, data})
        ) :: Type.stateful_t(success | error | unknown_pad_error_t, Child.state_t())
        when data: pad_data_t | any, success: {:ok, data}, error: {:error, reason :: any}
  def get_and_update_data(state, pad_ref, keys \\ [], f) do
    with {:ok, state} <- {assert_instance(state, pad_ref), state},
         {{:ok, out}, state} <-
           state
           |> Bunch.Access.get_and_update_in(data_keys(pad_ref, keys), f) do
      {{:ok, out}, state}
    else
      {{:error, reason}, state} -> {{:error, reason}, state}
    end
  end

  @spec get_and_update_data!(
          Child.state_t(),
          Pad.ref_t(),
          keys :: atom | [atom],
          (data -> {data, data})
        ) :: Type.stateful_t(data, Child.state_t())
        when data: pad_data_t | any
  def get_and_update_data!(state, pad_ref, keys \\ [], f) do
    :ok = assert_instance(state, pad_ref)

    state
    |> Bunch.Access.get_and_update_in(data_keys(pad_ref, keys), f)
  end

  @spec pop_data(Child.state_t(), Pad.ref_t()) ::
          Type.stateful_t({:ok, pad_data_t} | unknown_pad_error_t, Child.state_t())
  def pop_data(state, pad_ref) do
    with {:ok, state} <- {assert_instance(state, pad_ref), state} do
      {data, state} =
        state
        |> Bunch.Access.pop_in(data_keys(pad_ref))

      {{:ok, data}, state}
    end
  end

  @spec pop_data!(Child.state_t(), Pad.ref_t()) :: Type.stateful_t(pad_data_t, Child.state_t())
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

  @spec constraints_met?(pad_data_t, map) :: boolean
  defp constraints_met?(data, constraints) do
    constraints |> Enum.all?(fn {k, v} -> data[k] === v end)
  end

  @spec data_keys(Pad.ref_t(), keys :: atom | [atom]) :: [atom]
  defp data_keys(pad_ref, keys \\ []) do
    [:pads, :data, pad_ref | Bunch.listify(keys)]
  end
end
