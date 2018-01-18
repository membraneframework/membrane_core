defmodule Membrane.Element.Manager.State do
  @moduledoc false
  # Structure representing state of an Element.Manager. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Mixins.Log, tags: :core
  alias Membrane.Element
  alias Membrane.Element.Manager.PlaybackBuffer
  use Membrane.Helper
  alias __MODULE__

  @type internal_state_t :: any

  @type t :: %State{
    internal_state: internal_state_t,
    module: module,
    name: Element.name_t,
    playback_state: Membrane.Mixins.Playback.state_t,
    pads: %{optional(Element.Pad.name_t) => pid},
    message_bus: pid,
    playback_buffer: PlaybackBuffer.t,
    controlling_pid: nil,
    async_state_change: boolean(),
  }

  defstruct \
    internal_state: nil,
    module: nil,
    name: nil,
    playback_state: :stopped,
    pads: %{},
    message_bus: nil,
    controlling_pid: nil,
    async_state_change: false,
    playback_buffer: nil


  @doc """
  Initializes new state.
  """
  @spec new(module, Element.name_t) :: t
  def new(module, name) do
    # Initialize source pads

    with \
      {:ok, parsed_src_pads} <- handle_known_pads(:known_source_pads, :source, module),
      {:ok, parsed_sink_pads} <- handle_known_pads(:known_sink_pads, :sink, module)
    do

      %State{
        module: module,
        name: name,
        pads: %{
            data: %{},
            info: Map.merge(parsed_src_pads, parsed_sink_pads),
            dynamic_currently_linking: [],
          },
        internal_state: nil,
        controlling_pid: nil,
        playback_buffer: PlaybackBuffer.new
      }
        ~> (state -> {:ok, state})
    end
  end

  defp handle_known_pads(known_pads_fun, direction, module) do
    known_pads = cond do
      function_exported? module, known_pads_fun, 0 ->
        apply module, known_pads_fun, []
      true -> %{}
    end
    known_pads
      |> Helper.Enum.flat_map_with(fn params -> parse_pad params, direction end)
      ~>> ({:ok, parsed_pads} -> {:ok, parsed_pads |> Map.new})
  end

  def link_pad(state, {:dynamic, name, _no} = full_name, init_f) do
    with {:ok, data}
      <- state.pads.info[name]
        |> Helper.wrap_nil(:unknown_pad)
        ~>> (%{is_dynamic: false} -> {:error, :not_dynamic_pad})
    do
      {:ok, state} = state |> init_pad_data(full_name, data, init_f)
      state = state |> add_to_currently_linking(full_name)
      {:ok, state}
    end
  end

  def link_pad(state, name, init_f) do
    with {:ok, data}
      <- state.pads.info[name]
        |> Helper.wrap_nil(:unknown_pad)
        ~>> (%{is_dynamic: true} -> {:error, :not_static_pad})
    do
      {:ok, state} = state
        |> Helper.Struct.update_in([:pads, :info], & &1 |> Map.delete(name))
        |> init_pad_data(name, data, init_f)
      {:ok, state}
    end
  end

  defp init_pad_data(state, name, params, init_f) do
    params = params
      |> Map.merge(%{name: name, pid: nil, caps: nil, other_name: nil, sos: false, eos: false})
      |> init_f.()
    {:ok, state |> Helper.Struct.put_in([:pads, :data, name], params)}
  end

  defp add_to_currently_linking(state, name), do:
    state |> Helper.Struct.update_in([:pads, :dynamic_currently_linking], & [name | &1])

  def clear_currently_linking(state), do: state |> Helper.Struct.put_in([:pads, :dynamic_currently_linking], [])

  defp parse_pad({name, {:always, :push, caps}}, direction), do:
    do_parse_pad(name, :push, caps, direction)

  defp parse_pad({name, {:always, :pull, caps}}, :source), do:
    do_parse_pad(name, :pull, caps, :source, %{other_demand_in: nil})

  defp parse_pad({name, {:always, {:pull, demand_in: demand_in}, caps}}, :sink), do:
    do_parse_pad(name, :pull, caps, :sink, %{demand_in: demand_in})

  defp parse_pad({_name, {availability, _mode, _caps}}, _direction)
  when availability != :always
  do {:ok, []}
  end

  defp parse_pad(params, direction), do:
    warn_error "Invalid pad config: #{inspect params}, direction: #{inspect direction}",
      {:invalid_pad_config, params, direction: direction}

  defp do_parse_pad(name, mode, caps, direction, options \\ %{}) do
    with {:ok, name: name, is_dynamic: is_dynamic}
      <- parse_pad_name(name)
    do
      parsed_pad = %{
          name: name, mode: mode, direction: direction,
          accepted_caps: caps, is_dynamic: is_dynamic, options: options,
        }
      parsed_pad = parsed_pad
        |> Map.merge(if is_dynamic do %{current_id: 0} else %{} end)
      {:ok, [{name, parsed_pad}]}
    end
  end

  defp parse_pad_name({:dynamic, name})
  when is_atom(name) and not is_nil(name)
  do {:ok, name: name, is_dynamic: true}
  end

  defp parse_pad_name(name)
  when is_atom(name) and not is_nil(name)
  do {:ok, name: name, is_dynamic: false}
  end

  defp parse_pad_name(name) do
    warn_error "invlalid pad name, #{inspect name}", {:invalid_pad_name, name}
  end

  def resolve_pad_full_name(state, pad_name) do
    {full_name, state} = state
      |> Helper.Struct.get_and_update_in([:pads, :info, pad_name], fn
          nil -> :pop
          %{is_dynamic: true, current_id: id} = pad_info ->
            {{:dynamic, pad_name, id}, %{pad_info | current_id: id + 1}}
          %{is_dynamic: false} = pad_info -> {pad_name, pad_info}
        end)
    {full_name |> Helper.wrap_nil(:unknown_pad), state}
  end

  def get_pads_data(state, direction \\ :any)
  def get_pads_data(state, :any), do: state.pads.data
  def get_pads_data(state, direction), do: state.pads.data
    |> Enum.filter(fn {_, %{direction: ^direction}} -> true; _ -> false end)
    |> Enum.into(%{})

  def get_pad_data(state, pad_direction, pad_name, keys \\ [])
  def get_pad_data(state, pad_direction, pad_name, []) do
    with %{direction: dir} = data when pad_direction in [:any, dir] <-
      state.pads.data |> Map.get(pad_name)
    do {:ok, data}
    else _ -> {:error, :unknown_pad}
    end
  end
  def get_pad_data(state, pad_direction, pad_name, keys) do
    with {:ok, pad_data} <- get_pad_data(state, pad_direction, pad_name)
    do {:ok, pad_data |> Helper.Map.get_in(keys)}
    end
  end

  def get_pad_data!(state, pad_direction, pad_name, keys \\ []), do:
    get_pad_data(state, pad_direction, pad_name, keys)
      ~> ({:ok, pad_data} -> pad_data)

  def set_pad_data(state, pad_direction, pad, keys \\ [], v) do
    with {:ok, _data} <- state |> get_pad_data(pad_direction, pad)
    do
      keys = [:pads, :data, pad] ++ (keys |> Helper.listify)
      {:ok, state |> Helper.Struct.put_in(keys, v)}
    end
  end

  def update_pad_data(state, pad_direction, pad, keys \\ [], f) do
    with \
      {:ok, _pad_data} <- state |> get_pad_data(pad_direction, pad)
    do
      keys = [:pads, :data, pad] ++ (keys |> Helper.listify)
      state |> Helper.Struct.get_and_update_in(keys, &case f.(&1) do
          {:ok, res} -> {:ok, res}
          {:error, reason} -> {{:error, reason}, nil}
        end)
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_update_pad_data(state, pad_direction, pad, keys \\ [], f) do
    with \
      {:ok, _pad_data} <- state |> get_pad_data(pad_direction, pad)
    do
      keys = [:pads, :data, pad] ++ (keys |> Helper.listify)
      state |> Helper.Struct.get_and_update_in(keys, &case f.(&1) do
          {{:ok, out}, res} -> {{:ok, out}, res}
          {:error, reason} -> {{:error, reason}, nil}
        end)
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def pop_pad_data(state, pad_direction, pad) do
    with {:ok, %{name: name} = pad_data} <- get_pad_data(state, pad_direction, pad),
    do: state
      |> Helper.Struct.pop_in([:pads, :data, name])
      ~> ({_, state} -> {:ok, {pad_data, state}})
  end

  def remove_pad_data(state, pad_direction, pad) do
    with {:ok, {_out, state}} <- pop_pad_data(state, pad_direction, pad),
    do: {:ok, state}
  end

end
