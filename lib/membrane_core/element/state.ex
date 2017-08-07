defmodule Membrane.Element.State do
  @moduledoc false
  # Structure representing state of an element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Mixins.Log, tags: :core
  alias Membrane.Element
  use Membrane.Helper
  alias __MODULE__

  @type t :: %State{
    internal_state: any,
    module: module,
    playback_state: Membrane.Mixins.Playback.state_t,
    pads: %{optional(Element.pad_name_t) => pid},
    message_bus: pid,
  }

  defstruct \
    internal_state: nil,
    module: nil,
    playback_state: :stopped,
    pads: %{},
    message_bus: nil,
    playback_store: []


  @doc """
  Initializes new state.
  """
  @spec new(module, any) :: t
  def new(module, internal_state) do
    # Initialize source pads

    pads_data = Map.merge(
        handle_known_pads(:known_sink_pads, :sink, module),
        handle_known_pads(:known_source_pads, :source, module)
      )

    %State{
      module: module,
      pads: %{data: pads_data, names_by_pids: %{}, new: []},
      internal_state: internal_state,
    }
  end

  defp handle_known_pads(known_pads_fun, direction, module) do
    known_pads = cond do
      function_exported? module, known_pads_fun , 0 ->
        apply module, known_pads_fun, []
      true -> %{}
    end
    known_pads
      |> Enum.flat_map(fn params -> init_pad_data params, direction end)
      |> Enum.into(%{})
  end

  def add_pad(state, params, direction) do
    state = init_pad_data(params, direction)
      |> Enum.reduce(state, fn {name, data}, st -> st
        |> set_pad_data(direction, name, data)
        ~> ({:ok, st} ->
            Helper.Struct.update_in(st, [:pads, :new], & [{name, direction} | &1])
          )
        end)
    state
  end

  def clear_new_pads(state), do: state |> Helper.Struct.put_in([:pads, :new], [])

  defp init_pad_data({name, {:always, mode, caps}}, direction) do
    data = %{
        name: name, pid: nil, mode: mode,direction: direction,
        caps: nil, accepted_caps: caps,
      }
    [{name, data}]
  end
  defp init_pad_data(_params, _direction), do: []

  def get_pads_data(state, direction \\ :any)
  def get_pads_data(state, :any), do: state.pads.data
  def get_pads_data(state, direction), do: state.pads.data
    |> Enum.filter(fn {_, %{direction: ^direction}} -> true; _ -> false end)
    |> Enum.into(%{})

  def get_pad_data(state, pad_direction, pad_pid, keys \\ [])
  def get_pad_data(state, pad_direction, pad_pid, keys) when is_pid pad_pid do
    with {:ok, pad_name} <-
      state.pads.names_by_pids[pad_pid] |> Helper.wrap_nil(:unknown_pad)
    do get_pad_data(state, pad_direction, pad_name, keys)
    end
  end
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
    pad_data = state
      |> get_pad_data(pad_direction, pad)
      ~> (
          {:ok, pad_data} -> pad_data
          {:error, :unknown_pad} -> %{}
        )
      |> Helper.Map.put_in(keys, v)

    {:ok, state |> do_update_pad_data(pad_data)}
  end

  def update_pad_data(state, pad_direction, pad, keys \\ [], f) do
    with \
      {:ok, pad_data} <- get_pad_data(state, pad_direction, pad),
      {:ok, pad_data} <- pad_data
        |> Helper.Map.get_and_update_in(keys, &case f.(&1) do
            {:ok, res} -> {:ok, res}
            {:error, reason} -> {{:error, reason}, nil}
          end)
    do
      {:ok, state |> do_update_pad_data(pad_data)}
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_update_pad_data(state, pad_direction, pad, keys \\ [], f) do
    with \
      {:ok, pad_data} <- get_pad_data(state, pad_direction, pad),
      {{:ok, out}, pad_data} <- pad_data
        |> Helper.Map.get_and_update_in(keys, &case f.(&1) do
            {:ok, {out, res}} -> {{:ok, out}, res}
            {:error, reason} -> {{:error, reason}, nil}
          end)
    do {:ok, {out, state |> do_update_pad_data(pad_data)}}
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_update_pad_data(state, pad_data) do
    state
      |> Helper.Struct.put_in([:pads, :names_by_pids, pad_data.pid], pad_data.name)
      |> Helper.Struct.put_in([:pads, :data, pad_data.name], pad_data)
  end

  def pop_pad_data(state, pad_direction, pad) do
    with {:ok, %{name: name, pid: pid} = pad_data} <- get_pad_data(state, pad_direction, pad),
    do: state
      |> Helper.Struct.pop_in([:pads, :names_by_pids, pid])
      ~> ({_, state} -> state)
      |> Helper.Struct.pop_in([:pads, :data, name])
      ~> ({_, state} -> {:ok, {pad_data, state}})
  end

  def remove_pad_data(state, pad_direction, pad) do
    with {:ok, {_out, state}} <- pop_pad_data(state, pad_direction, pad),
    do: {:ok, state}
  end

  def playback_store_push(%State{playback_store: store} = state, fun, args) do
    %State{state | playback_store: [{fun, args} | store]}
  end

  def playback_store_eval(%State{playback_store: store, module: module} = state) do
    with \
      {:ok, state} <- store
        |> Enum.reverse
        |> Helper.Enum.reduce_with(state, fn {fun, args}, state -> apply module.base_module, fun, args ++ [state] end),
    do: {:ok, %State{state | playback_store: []}}
  end

end
