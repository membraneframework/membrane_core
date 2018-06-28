defmodule Membrane.Core.Element.PadModel do
  use Membrane.Helper

  def get_data(direction \\ :any, state)
  def get_data(:any, state), do: state.pads.data

  def get_data(direction, state),
    do:
      state.pads.data
      |> Enum.filter(fn
        {_, %{direction: ^direction}} -> true
        _ -> false
      end)
      |> Enum.into(%{})

  def get_data(pad_direction, pad_name, keys \\ [], state)

  def get_data(pad_direction, pad_name, [], state) do
    with %{direction: dir} = data when pad_direction in [:any, dir] <-
           state.pads.data |> Map.get(pad_name) do
      {:ok, data}
    else
      _ -> {:error, :unknown_pad}
    end
  end

  def get_data(pad_direction, pad_name, keys, state) do
    with {:ok, pad_data} <- get_data(pad_direction, pad_name, state) do
      {:ok, pad_data |> Helper.Map.get_in(keys)}
    end
  end

  def get_data!(pad_direction, pad_name, keys \\ [], state),
    do:
      get_data(pad_direction, pad_name, keys, state)
      ~> ({:ok, pad_data} -> pad_data)

  def set_data(pad_direction, pad, keys \\ [], v, state) do
    with {:ok, _data} <- get_data(pad_direction, pad, state) do
      keys = [:pads, :data, pad] ++ (keys |> Helper.listify())
      {:ok, state |> Helper.Struct.put_in(keys, v)}
    end
  end

  def update_data(pad_direction, pad, keys \\ [], f, state) do
    with {:ok, _pad_data} <- get_data(pad_direction, pad, state) do
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

  def get_update_data(pad_direction, pad, keys \\ [], f, state) do
    with {:ok, _pad_data} <- get_data(pad_direction, pad, state) do
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

  def pop_data(pad_direction, pad, state) do
    with {:ok, %{name: name} = pad_data} <- get_data(pad_direction, pad, state),
         do:
           state
           |> Helper.Struct.pop_in([:pads, :data, name])
           ~> ({_, state} -> {:ok, {pad_data, state}})
  end

  def remove_data(pad_direction, pad, state) do
    with {:ok, {_out, state}} <- pop_data(pad_direction, pad, state), do: {:ok, state}
  end
end
