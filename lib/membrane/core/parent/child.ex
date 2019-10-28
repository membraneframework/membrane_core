defmodule Membrane.Core.Parent.Child do
  @moduledoc false

  alias Membrane.{Clock, ParentError, ParentSpec, Sync}

  @type t :: %__MODULE__{
          name: Membrane.Child.name_t(),
          module: module,
          options: struct | nil,
          pid: pid | nil,
          clock: Clock.t() | nil,
          sync: Sync.t() | nil
        }

  @type resolved_t :: %__MODULE__{
          name: Membrane.Child.name_t(),
          module: module,
          options: struct | nil,
          pid: pid,
          clock: Clock.t(),
          sync: Sync.t()
        }

  defstruct [:name, :module, :options, :pid, :clock, :sync]

  @spec from_spec(ParentSpec.children_spec_t() | any) :: [t] | no_return
  def from_spec(children_spec) when is_map(children_spec) or is_list(children_spec) do
    children_spec |> Enum.map(&parse_child/1)
  end

  defp parse_child({name, %module{} = options}) do
    %__MODULE__{name: name, module: module, options: options}
  end

  defp parse_child({name, module}) when is_atom(module) do
    options = module |> Bunch.Module.struct()
    %__MODULE__{name: name, module: module, options: options}
  end

  defp parse_child(config) do
    raise ParentError, "Invalid children config: #{inspect(config, pretty: true)}"
  end
end
