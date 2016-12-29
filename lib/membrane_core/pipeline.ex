defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.
  """

  use Membrane.Mixins.Log
  use GenServer


  @type element_name_t :: String.t
  @type element_def_t :: {module, struct}
  @type element_defs_t :: %{required(element_name_t) => element_def_t}


  @doc """
  Starts the Pipeline based on given module and links it to the current
  process.

  Pipeline options are passed to module's handle_init callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(module, any, GenServer.options) :: GenServer.on_start
  def start_link(module, pipeline_options, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, pipeline_options = #{inspect(pipeline_options)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(__MODULE__, {module, pipeline_options}, process_options)
  end


  @doc """
  Does the same as `start_link/3` but starts process outside of supervision tree.
  """
  @spec start(module, any, GenServer.options) :: GenServer.on_start
  def start(module, pipeline_options, process_options \\ []) do
    debug("Start: module = #{inspect(module)}, pipeline_options = #{inspect(pipeline_options)}, process_options = #{inspect(process_options)}")
    GenServer.start(__MODULE__, {module, pipeline_options}, process_options)
  end


  @doc """
  Callback invoked on process initialization.

  It will receive second and third argument passed to `start_link/4` or `start/4`
  (list of enumerators and interval).

  It is supposed to return `{:ok, initial_elements, initial_state}` or
  `{:error, reason}`.

  Initial elements is a map where key is a string with element name unique
  within the pipeline, and value is a tuple of `{element_module, element_options}`
  that will be used to spawn the element process.
  """
  @callback handle_init(any, any) ::
    {:ok, element_defs_t, any} |
    {:error, any}


  # Private API

  @doc false
  def init({module, pipeline_options}) do
    case module.handle_init(pipeline_options) do
      {:ok, initial_elements, internal_state} ->

        case initial_elements |> spawn_elements(%{}) do
          {:ok, elements} ->
            {:ok, %{
              elements: elements,
              internal_state: internal_state,
            }}

          {:error, reason} ->
            {:stop, reason}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end


  defp spawn_elements(elements, acc) when is_map(elements) do
    spawn_elements(Map.to_list(elements), acc)
  end

  defp spawn_elements([], acc) do
    acc
  end

  defp spawn_elements([{name, {module, options}}|tail], acc) do
    case Membrane.Element.start_link(module, options) do
      {:ok, pid} ->
        spawn_elements(tail, Map.put(acc, name, pid))

      {:error, reason} ->
        {:error, reason}
    end
  end


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Pipeline
    end
  end
end
