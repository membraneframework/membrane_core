defmodule Membrane.Core.Child.PadModel do
  @moduledoc false

  # Utility functions for veryfying and manipulating pads and their data.

  use Bunch

  alias Membrane.Core.Child
  alias Membrane.Core.Element.EffectiveFlowController
  alias Membrane.{Pad, UnknownPadError}

  @type bin_pad_data :: %Membrane.Bin.PadData{
          ref: Membrane.Pad.ref(),
          options: Membrane.ChildrenSpec.pad_options(),
          link_id: Membrane.Core.Parent.Link.id(),
          endpoint: Membrane.Core.Parent.Link.Endpoint.t() | nil,
          linked?: boolean(),
          response_received?: boolean(),
          spec_ref: Membrane.Core.Parent.ChildLifeController.spec_ref(),
          availability: Pad.availability(),
          direction: Pad.direction(),
          name: Pad.name()
        }

  @type element_pad_data :: %Membrane.Element.PadData{
          availability: Pad.availability(),
          stream_format: Membrane.StreamFormat.t() | nil,
          demand_snapshot: integer() | nil,
          start_of_stream?: boolean(),
          end_of_stream?: boolean(),
          direction: Pad.direction(),
          flow_control: Pad.flow_control(),
          other_effective_flow_control: EffectiveFlowController.effective_flow_control() | nil,
          name: Pad.name(),
          ref: Pad.ref(),
          demand_unit: Membrane.Buffer.Metric.unit() | nil,
          other_demand_unit: Membrane.Buffer.Metric.unit() | nil,
          pid: pid,
          other_ref: Pad.ref(),
          sticky_messages: [Membrane.Event.t()],
          input_queue: Membrane.Core.Element.InputQueue.t() | nil,
          options: %{optional(atom) => any},
          auto_demand_size: pos_integer() | nil,
          associated_pads: [Pad.ref()] | nil,
          sticky_events: [Membrane.Event.t()]
        }

  @type pad_data :: bin_pad_data | element_pad_data

  @type pads_data :: %{Pad.ref() => pad_data}

  @type pad_info :: %{
          required(:availability) => Pad.availability(),
          required(:direction) => Pad.direction(),
          required(:name) => Pad.name(),
          required(:accepted_formats_str) => String.t(),
          optional(:flow_control) => Pad.flow_control(),
          optional(:demand_unit) => Membrane.Buffer.Metric.unit(),
          optional(:other_demand_unit) => Membrane.Buffer.Metric.unit()
        }

  @type pads_info :: %{Pad.name() => pad_info}

  @spec assert_instance(Child.state(), Pad.ref()) ::
          :ok | {:error, :unknown_pad}
  def assert_instance(%{pads_data: data}, pad_ref) when is_map_key(data, pad_ref), do: :ok
  def assert_instance(_state, _pad_ref), do: {:error, :unknown_pad}

  @spec assert_instance!(Child.state(), Pad.ref()) :: :ok
  def assert_instance!(state, pad_ref) do
    :ok = assert_instance(state, pad_ref)
  end

  defmacro assert_data(state, pad_ref, pattern) do
    quote do
      use Bunch

      withl get: {:ok, data} <- unquote(__MODULE__).get_data(unquote(state), unquote(pad_ref)),
            match: unquote(pattern) <- data do
        :ok
      else
        get: {:error, :unknown_pad} -> {:error, :unknown_pad}
        match: _data -> {:error, :no_match}
      end
    end
  end

  defmacro assert_data!(state, pad_ref, pattern) do
    quote do
      pad_ref = unquote(pad_ref)
      state = unquote(state)

      case unquote(__MODULE__).get_data!(state, pad_ref) do
        unquote(pattern) ->
          :ok

        data ->
          raise Membrane.PadError, """
          Assertion on data of the pad #{inspect(pad_ref)} failed, pattern: #{unquote(Macro.to_string(pattern))}
          Pad data: #{inspect(data, pretty: true)}
          """
      end
    end
  end

  @spec filter_refs_by_data(Child.state(), constraints :: map) :: [Pad.ref()]
  def filter_refs_by_data(state, constraints \\ %{})

  def filter_refs_by_data(state, constraints) when constraints == %{} do
    state.pads_data |> Map.keys()
  end

  def filter_refs_by_data(state, constraints) do
    state.pads_data
    |> Enum.filter(fn {_name, data} -> data |> constraints_met?(constraints) end)
    |> Keyword.keys()
  end

  @spec filter_data(Child.state(), constraints :: map) :: %{atom => pad_data}
  def filter_data(state, constraints \\ %{})

  def filter_data(state, constraints) when constraints == %{} do
    state.pads_data
  end

  def filter_data(state, constraints) do
    state.pads_data
    |> Enum.filter(fn {_name, data} -> data |> constraints_met?(constraints) end)
    |> Map.new()
  end

  # TODO: leave the main branch only when we stop supporting elixir prior 1.14
  if Version.match?(System.version(), ">= 1.14.0-dev") do
    alias Membrane.Core.Helper.FastMap
    require FastMap

    defmacro get_data(state, pad_ref, keys \\ []) do
      keys = Bunch.listify(keys)
      pad_data_var = Macro.unique_var(:pad_data, __MODULE__)

      quote do
        pad_ref_var = unquote(pad_ref)

        case unquote(state) do
          %{pads_data: %{^pad_ref_var => unquote(pad_data_var)}} ->
            {:ok, unquote(FastMap.generate_get_in!(pad_data_var, keys))}

          _state ->
            {:error, :unknown_pad}
        end
      end
    end

    defmacro get_data!(state, pad_ref, keys \\ []) do
      keys = Bunch.listify(keys)

      FastMap.generate_get_in!(state, [:pads_data, pad_ref] ++ keys)
      |> wrap_with_reraise(pad_ref, state)
    end

    defmacro set_data!(state, pad_ref, keys \\ [], value) do
      keys = Bunch.listify(keys)

      FastMap.generate_set_in!(state, [:pads_data, pad_ref] ++ keys, value)
      |> wrap_with_reraise(pad_ref, state)
    end

    defmacro set_data(state, pad_ref, keys \\ [], value) do
      keys = Bunch.listify(keys)

      {:ok, FastMap.generate_set_in!(state, [:pads_data, pad_ref] ++ keys, value)}
      |> wrap_with_pad_check(pad_ref, state)
    end

    defmacro update_data!(state, pad_ref, keys \\ [], f) do
      keys = Bunch.listify(keys)

      FastMap.generate_update_in!(state, [:pads_data, pad_ref] ++ keys, f)
      |> wrap_with_reraise(pad_ref, state)
    end

    defmacro update_data(state, pad_ref, keys \\ [], f) do
      keys = Bunch.listify(keys)

      FastMap.generate_get_and_update_in!(state, [:pads_data, pad_ref] ++ keys, f)
      |> wrap_with_pad_check(pad_ref, state)
    end

    defmacro get_and_update_data!(state, pad_ref, keys \\ [], f) do
      keys = Bunch.listify(keys)

      FastMap.generate_get_and_update_in!(state, [:pads_data, pad_ref] ++ keys, f)
      |> wrap_with_reraise(pad_ref, state)
    end

    defmacro get_and_update_data(state, pad_ref, keys \\ [], f) do
      FastMap.generate_get_and_update_in!(state, [:pads_data, pad_ref] ++ keys, f)
      |> wrap_with_pad_check(pad_ref, state)
    end
  else
    @spec get_data(Child.state(), Pad.ref()) ::
            {:ok, pad_data() | any} | {:error, :unknown_pad}
    def get_data(%{pads_data: data}, pad_ref) do
      case Map.fetch(data, pad_ref) do
        {:ok, pad_data} -> {:ok, pad_data}
        :error -> {:error, :unknown_pad}
      end
    end

    @spec get_data(Child.state(), Pad.ref(), keys :: atom | [atom]) ::
            {:ok, pad_data | any} | {:error, :unknown_pad}
    def get_data(%{pads_data: data}, pad_ref, keys)
        when is_map_key(data, pad_ref) and is_list(keys) do
      data
      |> get_in([pad_ref | keys])
      ~> {:ok, &1}
    end

    def get_data(%{pads_data: data}, pad_ref, key)
        when is_map_key(data, pad_ref) and is_atom(key) do
      data
      |> get_in([pad_ref, key])
      ~> {:ok, &1}
    end

    def get_data(_state, _pad_ref, _keys), do: {:error, :unknown_pad}

    @spec get_data!(Child.state(), Pad.ref()) :: pad_data | any
    def get_data!(state, pad_ref) do
      {:ok, pad_data} = get_data(state, pad_ref)
      pad_data
    end

    @spec get_data!(Child.state(), Pad.ref(), keys :: atom | [atom]) :: pad_data | any
    def get_data!(state, pad_ref, keys) do
      {:ok, pad_data} = get_data(state, pad_ref, keys)
      pad_data
    end

    @spec set_data(Child.state(), Pad.ref(), keys :: atom | [atom], value :: term()) ::
            Bunch.Type.stateful_t(:ok | {:error, :unknown_pad}, Child.state())
    def set_data(state, pad_ref, keys \\ [], value) do
      case assert_instance(state, pad_ref) do
        :ok ->
          put_in(state, data_keys(pad_ref, keys), value)
          ~> {:ok, &1}

        {:error, reason} ->
          {{:error, reason}, state}
      end
    end

    @spec set_data!(Child.state(), Pad.ref(), keys :: atom | [atom], value :: term()) ::
            Child.state()
    def set_data!(state, pad_ref, keys \\ [], value) do
      {:ok, state} = set_data(state, pad_ref, keys, value)
      state
    end

    @spec update_data(
            Child.state(),
            Pad.ref(),
            keys :: atom | [atom],
            (data -> {:ok | error, data})
          ) ::
            Bunch.Type.stateful_t(:ok | error | {:error, :unknown_pad}, Child.state())
          when data: pad_data | any, error: {:error, reason :: any}
    def update_data(state, pad_ref, keys \\ [], f) do
      case assert_instance(state, pad_ref) do
        :ok ->
          state |> get_and_update_in(data_keys(pad_ref, keys), f)

        {:error, reason} ->
          {{:error, reason}, state}
      end
    end

    @spec update_data!(Child.state(), Pad.ref(), keys :: atom | [atom], (data -> data)) ::
            Child.state()
          when data: pad_data | any
    def update_data!(state, pad_ref, keys \\ [], f) do
      :ok = assert_instance(state, pad_ref)

      state
      |> update_in(data_keys(pad_ref, keys), f)
    end

    @spec get_and_update_data(
            Child.state(),
            Pad.ref(),
            keys :: atom | [atom],
            (data -> {success | error, data})
          ) :: Bunch.Type.stateful_t(success | error | {:error, :unknown_pad}, Child.state())
          when data: pad_data | any, success: {:ok, data}, error: {:error, reason :: any}
    def get_and_update_data(state, pad_ref, keys \\ [], f) do
      case assert_instance(state, pad_ref) do
        :ok ->
          state
          |> get_and_update_in(data_keys(pad_ref, keys), f)

        {:error, reason} ->
          {{:error, reason}, state}
      end
    end

    @spec get_and_update_data!(
            Child.state(),
            Pad.ref(),
            keys :: atom | [atom],
            (data -> {data, data})
          ) :: Bunch.Type.stateful_t(data, Child.state())
          when data: pad_data | any
    def get_and_update_data!(state, pad_ref, keys \\ [], f) do
      :ok = assert_instance(state, pad_ref)

      state
      |> get_and_update_in(data_keys(pad_ref, keys), f)
    end

    @spec data_keys(Pad.ref(), keys :: atom | [atom]) :: [atom]
    @compile {:inline, data_keys: 2}
    defp data_keys(pad_ref, keys)

    defp data_keys(pad_ref, keys) when is_list(keys) do
      [:pads_data, pad_ref | keys]
    end

    defp data_keys(pad_ref, key) do
      [:pads_data, pad_ref, key]
    end
  end

  @spec pop_data(Child.state(), Pad.ref()) ::
          {{:ok, pad_data} | {:error, :unknown_pad}, Child.state()}
  def pop_data(state, pad_ref) do
    with :ok <- assert_instance(state, pad_ref) do
      {data, state} = pop_in(state, [:pads_data, pad_ref])
      {{:ok, data}, state}
    else
      {:error, :unknown_pad} -> {{:error, :unknown_pad}, state}
    end
  end

  @spec pop_data!(Child.state(), Pad.ref()) :: {pad_data, Child.state()}
  def pop_data!(state, pad_ref) do
    case pop_data(state, pad_ref) do
      {{:ok, pad_data}, state} -> {pad_data, state}
      {{:error, :unknown_pad}, state} -> raise UnknownPadError, pad: pad_ref, module: state.module
    end
  end

  @spec delete_data(Child.state(), Pad.ref()) ::
          {:ok | {:error, :unknown_pad}, Child.state()}
  def delete_data(state, pad_ref) do
    with {{:ok, _out}, state} <- pop_data(state, pad_ref) do
      {:ok, state}
    end
  end

  @spec delete_data!(Child.state(), Pad.ref()) :: Child.state()
  def delete_data!(state, pad_ref) do
    {_data, state} = pop_data!(state, pad_ref)
    state
  end

  @spec constraints_met?(pad_data, map) :: boolean
  defp constraints_met?(data, constraints) do
    constraints |> Enum.all?(fn {k, v} -> data[k] === v end)
  end

  defp wrap_with_pad_check(code, pad_ref, state) do
    quote do
      pad_ref_var = unquote(pad_ref)

      case unquote(state) do
        %{pads_data: %{^pad_ref_var => _pad_data}} -> unquote(code)
        state -> {{:error, :unknown_pad}, state}
      end
    end
  end

  defp wrap_with_reraise(code, pad_ref, state) do
    quote do
      try do
        unquote(code)
      rescue
        e in MatchError ->
          pad_ref = unquote(pad_ref)
          state = unquote(state)

          case unquote(__MODULE__).assert_instance(state, pad_ref) do
            :ok ->
              reraise e, __STACKTRACE__

            {:error, :unknown_pad} ->
              reraise UnknownPadError, [pad: pad_ref, module: state.module], __STACKTRACE__
          end
      end
    end
  end
end
