defmodule Membrane.Element.Manager.CapsMatcher do
  def any(), do: %{}

  def match?(:any, %_{}), do: :ok

  def match?(specs, %_{} = caps) when is_list(specs) do
    if specs |> Enum.any?(fn spec -> __MODULE__.match?(spec, caps) end) do
      :ok
    else
      :invalid_caps
    end
  end

  def match?(%{type: type} = spec, %_{} = caps) do
    with true <- type == caps.__struct__,
         :ok  <- spec |> Map.delete(:type) |> __MODULE__.match?(caps)
    do
      :ok
    else
      _ -> :invalid_caps
    end
  end

  def match?(%{} = spec, %_{} = caps) do
    if spec |> Enum.all?(fn {key, spec_value} -> match_value(spec_value, Map.get(caps, key)) end) do
      :ok
    else
      :invalid_caps
    end
  end

  defp match_value(spec, value) when is_list(spec) do
    value in spec
  end

  defp match_value({min, max}, value) do
    min <= value && value <= max
  end

  defp match_value(spec, value) do
    spec == value
  end
end
