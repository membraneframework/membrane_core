defmodule Membrane.Element.State do
  @moduledoc false
  # Structure representing state of an element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Mixins.Log
  alias Membrane.Element
  use Membrane.Helper

  @type t :: %Membrane.Element.State{
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
    message_bus: nil


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

    %Membrane.Element.State{
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
    init_pad_data(params, direction)
      |> Enum.reduce(state, fn {name, data}, st -> st
        |> set_pad_data(direction, name, data)
        |> Helper.Struct.update_in([:pads, :new], & [name | &1])
        end)
  end

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
      state.pads.names_by_pids |> Helper.Map.get_wrap(pad_pid, :unknown_pad)
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

  def set_pad_data(state, pad_direction, pad_name, keys \\ [], v) do
    with \
      {:ok, pad_data} <- get_pad_data(state, pad_direction, pad_name)
    do
      pad_data = pad_data |> Helper.Map.put_in(keys, v)
      {:ok, state |> do_update_pad_data(pad_name, pad_data)}
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_pad_data(state, pad_direction, pad_name, keys \\ [], f) do
    with \
      {:ok, pad_data} <- get_pad_data(state, pad_direction, pad_name),
      {:ok, pad_data} <- pad_data
        |> Helper.Map.get_and_update_in(keys, &case f.(&1) do
            {:ok, res} -> {:ok, res}
            {:error, reason} -> {{:error, reason}, nil}
          end)
    do
      {:ok, state |> do_update_pad_data(pad_name, pad_data)}
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_update_pad_data(state, pad_direction, pad_name, keys \\ [], f) do
    with \
      {:ok, pad_data} <- get_pad_data(state, pad_direction, pad_name),
      {{:ok, out}, pad_data} <- pad_data
        |> Helper.Map.get_and_update_in(keys, &case f.(&1) do
            {:ok, {out, res}} -> {{:ok, out}, res}
            {:error, reason} -> {{:error, reason}, nil}
          end)
    do {:ok, {out, state |> do_update_pad_data(pad_name, pad_data)}}
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_update_pad_data(state, pad_name, pad_data) do
    state
      |> Helper.Struct.put_in([:pads, :names_by_pids, pad_data.pid], pad_name)
      |> Helper.Struct.put_in([:pads, :data, pad_name], pad_data)
  end
end
