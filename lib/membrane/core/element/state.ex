defmodule Membrane.Core.Element.State do
  @moduledoc false
  # Structure representing state of an Core.Element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Mixins.Log, tags: :core
  alias Membrane.{Core, Element}
  alias Core.Element.PlaybackBuffer
  alias Element.Pad
  alias Element.Base.Mixin.CommonBehaviour
  use Membrane.Helper
  alias __MODULE__, as: ThisModule
  alias Membrane.Core.Mixins.{Playback, Playbackable}
  require Pad

  @type t :: %__MODULE__{
          internal_state: CommonBehaviour.internal_state_t(),
          module: module,
          type: Element.type_t(),
          name: Element.name_t(),
          playback: Playback.t(),
          pads: %{optional(Element.Pad.name_t()) => pid},
          message_bus: pid,
          playback_buffer: PlaybackBuffer.t(),
          controlling_pid: nil
        }

  defstruct internal_state: nil,
            module: nil,
            type: nil,
            name: nil,
            playback: %Playback{},
            pads: %{},
            message_bus: nil,
            controlling_pid: nil,
            playback_buffer: nil

  defimpl Playbackable, for: __MODULE__ do
    use Playbackable.Default
    def get_controlling_pid(%ThisModule{controlling_pid: pid}), do: pid
  end

  @doc """
  Initializes new state.
  """
  @spec new(module, Element.name_t()) :: {:ok, t} | {:error, any}
  def new(module, name) do
    with {:ok, parsed_src_pads} <- handle_known_pads(:known_source_pads, :source, module),
         {:ok, parsed_sink_pads} <- handle_known_pads(:known_sink_pads, :sink, module) do
      %__MODULE__{
        module: module,
        type: module.membrane_element_type(),
        name: name,
        pads: %{
          data: %{},
          info: Map.merge(parsed_src_pads, parsed_sink_pads),
          dynamic_currently_linking: []
        },
        internal_state: nil,
        controlling_pid: nil,
        playback_buffer: PlaybackBuffer.new()
      }
      ~> (state -> {:ok, state})
    end
  end

  defp handle_known_pads(known_pads_fun, direction, module) do
    known_pads =
      cond do
        function_exported?(module, known_pads_fun, 0) ->
          apply(module, known_pads_fun, [])

        true ->
          %{}
      end

    known_pads
    |> Helper.Enum.flat_map_with(fn params -> parse_pad(params, direction) end)
    ~>> ({:ok, parsed_pads} -> {:ok, parsed_pads |> Map.new()})
  end

  def link_pad(state, {:dynamic, name, _no} = full_name, direction, init_f) do
    with %{direction: ^direction, is_dynamic: true} = data <- state.pads.info[name] do
      {:ok, state} = state |> init_pad_data(full_name, data, init_f)
      state = state |> add_to_currently_linking(full_name)
      {:ok, state}
    else
      %{direction: actual_direction} ->
        {:error, {:invalid_pad_direction, [expected: direction, actual: actual_direction]}}

      %{is_dynamic: false} ->
        {:error, :not_dynamic_pad}

      nil ->
        {:error, :unknown_pad}
    end
  end

  def link_pad(state, name, direction, init_f) do
    with %{direction: ^direction, is_dynamic: false} = data <- state.pads.info[name] do
      state
      |> Helper.Struct.update_in([:pads, :info], &(&1 |> Map.delete(name)))
      |> init_pad_data(name, data, init_f)
    else
      %{direction: actual_direction} ->
        {:error, {:invalid_pad_direction, [expected: direction, actual: actual_direction]}}

      %{is_dynamic: true} ->
        {:error, :not_static_pad}

      nil ->
        case get_pad_data(state, name, direction) do
          {:ok, _} -> {:error, :already_linked}
          _ -> {:error, :unknown_pad}
        end
    end
  end

  defp init_pad_data(state, name, params, init_f) do
    params =
      params
      |> Map.merge(%{name: name, pid: nil, caps: nil, other_name: nil, sos: false, eos: false})
      |> init_f.()

    {:ok, state |> Helper.Struct.put_in([:pads, :data, name], params)}
  end

  defp add_to_currently_linking(state, name),
    do: state |> Helper.Struct.update_in([:pads, :dynamic_currently_linking], &[name | &1])

  def clear_currently_linking(state),
    do: state |> Helper.Struct.put_in([:pads, :dynamic_currently_linking], [])

  defp parse_pad({name, {availability, :push, caps}}, direction)
       when is_atom(name) and Pad.is_availability(availability) do
    do_parse_pad(name, availability, :push, caps, direction)
  end

  defp parse_pad({name, {availability, :pull, caps}}, :source)
       when is_atom(name) and Pad.is_availability(availability) do
    do_parse_pad(name, availability, :pull, caps, :source, %{other_demand_in: nil})
  end

  defp parse_pad({name, {availability, {:pull, demand_in: demand_in}, caps}}, :sink)
       when is_atom(name) and Pad.is_availability(availability) do
    do_parse_pad(name, availability, :pull, caps, :sink, %{demand_in: demand_in})
  end

  defp parse_pad(params, direction),
    do:
      warn_error(
        "Invalid pad config: #{inspect(params)}, direction: #{inspect(direction)}",
        {:invalid_pad_config, params, direction: direction}
      )

  defp do_parse_pad(name, availability, mode, caps, direction, options \\ %{}) do
    parsed_pad =
      %{
        name: name,
        mode: mode,
        direction: direction,
        accepted_caps: caps,
        availability: availability,
        options: options
      }
      |> Map.merge(
        if availability |> Pad.availability_mode() == :dynamic do
          %{current_id: 0, is_dynamic: true}
        else
          %{is_dynamic: false}
        end
      )

    {:ok, [{name, parsed_pad}]}
  end

  def resolve_pad_full_name(state, pad_name) do
    {full_name, state} =
      state
      |> Helper.Struct.get_and_update_in([:pads, :info, pad_name], fn
        nil ->
          :pop

        %{is_dynamic: true, current_id: id} = pad_info ->
          {{:dynamic, pad_name, id}, %{pad_info | current_id: id + 1}}

        %{is_dynamic: false} = pad_info ->
          {pad_name, pad_info}
      end)

    {full_name |> Helper.wrap_nil(:unknown_pad), state}
  end

  def get_pads_data(state, direction \\ :any)
  def get_pads_data(state, :any), do: state.pads.data

  def get_pads_data(state, direction),
    do:
      state.pads.data
      |> Enum.filter(fn
        {_, %{direction: ^direction}} -> true
        _ -> false
      end)
      |> Enum.into(%{})

  def get_pad_data(state, pad_direction, pad_name, keys \\ [])

  def get_pad_data(state, pad_direction, pad_name, []) do
    with %{direction: dir} = data when pad_direction in [:any, dir] <-
           state.pads.data |> Map.get(pad_name) do
      {:ok, data}
    else
      _ -> {:error, :unknown_pad}
    end
  end

  def get_pad_data(state, pad_direction, pad_name, keys) do
    with {:ok, pad_data} <- get_pad_data(state, pad_direction, pad_name) do
      {:ok, pad_data |> Helper.Map.get_in(keys)}
    end
  end

  def get_pad_data!(state, pad_direction, pad_name, keys \\ []),
    do:
      get_pad_data(state, pad_direction, pad_name, keys)
      ~> ({:ok, pad_data} -> pad_data)

  def set_pad_data(state, pad_direction, pad, keys \\ [], v) do
    with {:ok, _data} <- state |> get_pad_data(pad_direction, pad) do
      keys = [:pads, :data, pad] ++ (keys |> Helper.listify())
      {:ok, state |> Helper.Struct.put_in(keys, v)}
    end
  end

  def update_pad_data(state, pad_direction, pad, keys \\ [], f) do
    with {:ok, _pad_data} <- state |> get_pad_data(pad_direction, pad) do
      keys = [:pads, :data, pad] ++ (keys |> Helper.listify())

      state
      |> Helper.Struct.get_and_update_in(
        keys,
        &case f.(&1) do
          {:ok, res} -> {:ok, res}
          {:error, reason} -> {{:error, reason}, nil}
        end
      )
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_update_pad_data(state, pad_direction, pad, keys \\ [], f) do
    with {:ok, _pad_data} <- state |> get_pad_data(pad_direction, pad) do
      keys = [:pads, :data, pad] ++ (keys |> Helper.listify())

      state
      |> Helper.Struct.get_and_update_in(
        keys,
        &case f.(&1) do
          {{:ok, out}, res} -> {{:ok, out}, res}
          {:error, reason} -> {{:error, reason}, nil}
        end
      )
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def pop_pad_data(state, pad_direction, pad) do
    with {:ok, %{name: name} = pad_data} <- get_pad_data(state, pad_direction, pad),
         do:
           state
           |> Helper.Struct.pop_in([:pads, :data, name])
           ~> ({_, state} -> {:ok, {pad_data, state}})
  end

  def remove_pad_data(state, pad_direction, pad) do
    with {:ok, {_out, state}} <- pop_pad_data(state, pad_direction, pad), do: {:ok, state}
  end
end
