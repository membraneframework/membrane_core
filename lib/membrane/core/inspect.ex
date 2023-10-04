defmodule Membrane.Core.Inspect do
  @moduledoc false

  alias Inspect.Algebra
  alias Membrane.Core.Component

  @doc """
  A function, that inspects passed state sorting its fields withing the order in which
  they occur in the list passed to `defstruct`.
  """
  @spec inspect(Component.state(), Inspect.Opts.t()) :: Inspect.Algebra.t()
  def inspect(%state_module{} = state, opts) do
    ordered_fields =
      state_module.__info__(:struct)
      |> Enum.map(& &1.field)

    field_to_doc_fun =
      fn field, opts ->
        value_doc =
          Map.fetch!(state, field)
          |> Algebra.to_doc(opts)

        Algebra.concat("#{Atom.to_string(field)}: ", value_doc)
      end

    Algebra.container_doc(
      "%#{Kernel.inspect(state_module)}{",
      ordered_fields,
      "}",
      opts,
      field_to_doc_fun,
      break: :strict
    )
  end
end

[Pipeline, Bin, Element]
|> Enum.map(fn component ->
  state_module = Module.concat([Membrane.Core, component, State])

  defimpl Inspect, for: state_module do
    @spec inspect(unquote(state_module).t(), Inspect.Opts.t()) :: Inspect.Algebra.t()
    defdelegate inspect(state, opts), to: Membrane.Core.Inspect
  end
end)
