defmodule Membrane.Core.ParentUtils do
  use Bunch

  alias Membrane.Element
  alias Membrane.Bin
  alias Membrane.ParentError
  alias Membrane.Core.ParentState

  require Element
  require Bin

  import Membrane.Log

  @type child_name_t :: Element.name_t() | Bin.name_t()
  @typep parsed_child_t :: %{name: child_name_t(), module: module, options: Keyword.t()}

  defguard is_child_name(term) when Element.is_element_name(term) or Bin.is_bin_name(term)

  @spec parse_children(Spec.children_spec_t() | any) :: [parsed_child_t]
  def parse_children(children) when is_map(children) or is_list(children),
    do: children |> Enum.map(&parse_child/1)

  def parse_child({name, %module{} = options})
      when is_child_name(name) do
    %{name: name, module: module, options: options}
  end

  def parse_child({name, module})
      when is_child_name(name) and is_atom(module) do
    options = module |> Bunch.Module.struct()
    %{name: name, module: module, options: options}
  end

  def parse_child(config) do
    raise ParentError, "Invalid children config: #{inspect(config, pretty: true)}"
  end

  @spec check_if_children_names_unique([parsed_child_t], Bin.State.t() | Pipeline.State.t()) ::
          Type.try_t()
  def check_if_children_names_unique(children, state) do
    %{children: state_children} = state

    children
    |> Enum.map(& &1.name)
    |> Kernel.++(Map.keys(state_children))
    |> Bunch.Enum.duplicates()
    ~> (
      [] ->
        :ok

      duplicates ->
        raise ParentError, "Duplicated names in children specification: #{inspect(duplicates)}"
    )
  end

  @spec start_children([parsed_child_t]) :: [State.child_t()]
  def start_children(children) do
    debug("Starting children: #{inspect(children)}")

    children |> Enum.map(&start_child/1)
  end

  @spec add_children([ParentUtils.parsed_child_t()], Bin.State.t() | Pipeline.State.t()) ::
          Type.stateful_try_t(State.t())
  def add_children(children, state) do
    children
    |> Bunch.Enum.try_reduce(state, fn {name, pid}, state ->
      state |> ParentState.add_child(name, pid)
    end)
  end

  defp start_child(%{module: module} = spec) do
    case child_type(module) do
      :bin ->
        start_child_bin(spec)

      :element ->
        start_child_element(spec)
    end
  end

  defp child_type(module) do
    if module |> Bunch.Module.check_behaviour(:membrane_bin?) do
      :bin
    else
      :element
    end
  end

  # Recursion that starts children processes, case when both module and options
  # are provided.
  defp start_child_element(%{name: name, module: module, options: options}) do
    debug("Pipeline: starting child: name: #{inspect(name)}, module: #{inspect(module)}")

    with {:ok, pid} <- Element.start_link(self(), module, name, options),
         :ok <- Element.set_controlling_pid(pid, self()) do
      {name, pid}
    else
      {:error, reason} ->
        raise ParentError,
              "Cannot start child #{inspect(name)}, \
              reason: #{inspect(reason, pretty: true)}"
    end
  end

  defp start_child_bin(%{name: name, module: module, options: options}) do
    with {:ok, pid} <- Bin.start_link(name, module, options, []),
         :ok <- Bin.set_controlling_pid(pid, self()) do
      {name, pid}
    else
      {:error, reason} ->
        raise ParentError,
              "Cannot start child #{inspect(name)}, \
              reason: #{inspect(reason, pretty: true)}"
    end
  end
end
