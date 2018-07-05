defmodule Membrane.Core.Element.PadModel do
  use Membrane.Helper

  def assert_instance(pad_name, state) do
    with true <- state.pads.data |> Map.has_key?(pad_name) do
      :ok
    else
      false -> {:error, {:unknown_pad, pad_name}}
    end
  end

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

  def filter_names_by_data(constraints \\ %{}, state)

  def filter_names_by_data(constraints, state) when constraints == %{} do
    state.pads.data |> Map.keys()
  end

  def filter_names_by_data(constraints, state) do
    state.pads.data
    |> Enum.filter(fn {_name, data} -> data |> constraints_met?(constraints) end)
    |> Keyword.keys()
  end

  def filter_data(constraints \\ %{}, state)

  def filter_data(constraints, state) when constraints == %{} do
    state.pads.data
  end

  def filter_data(constraints, state) do
    state.pads.data
    |> Enum.filter(fn {_name, data} -> data |> constraints_met?(constraints) end)
    |> Map.new()
  end

  def get_data(pad_name, keys \\ [], state) do
    with :ok <- assert_instance(pad_name, state) do
      state
      |> Helper.Struct.get_in(data_keys(pad_name, keys))
      ~> {:ok, &1}
    end
  end

  def get_data!(pad_name, keys \\ [], state) do
    get_data(pad_name, keys, state)
    ~> ({:ok, pad_data} -> pad_data)
  end

  def set_data(pad_name, keys \\ [], v, state) do
    with :ok <- assert_instance(pad_name, state) do
      state
      |> Helper.Struct.put_in(data_keys(pad_name, keys), v)
      ~> {:ok, &1}
    end
  end

  def update_data(pad_name, keys \\ [], f, state) do
    with :ok <- assert_instance(pad_name, state) do
      state
      |> Helper.Struct.get_and_update_in(
        data_keys(pad_name, keys),
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

  def get_and_update_data(pad_name, keys \\ [], f, state) do
    with :ok <- assert_instance(pad_name, state) do
      state
      |> Helper.Struct.get_and_update_in(
        data_keys(pad_name, keys),
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

  def pop_data(pad_name, state) do
    with :ok <- assert_instance(pad_name, state) do
      state
      |> Helper.Struct.pop_in(data_keys(pad_name))
      ~> {:ok, &1}
    end
  end

  def delete_data(pad_name, state) do
    with {:ok, {_out, state}} <- pop_data(pad_name, state) do
      {:ok, state}
    end
  end

  defp constraints_met?(data, constraints) do
    constraints |> Enum.all?(fn {k, v} -> data[k] === v end)
  end

  defp data_keys(pad_name, keys \\ []) do
    [:pads, :data, pad_name | Helper.listify(keys)]
  end
end
