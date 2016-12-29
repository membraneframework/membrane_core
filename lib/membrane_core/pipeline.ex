defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.
  """

  use Membrane.Mixins.Log
  use GenServer


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

  It is supposed to return `{:ok, initial_state}` or `{:error, reason}`.
  """
  @callback handle_init([module], pos_integer) ::
    {:ok, any} |
    {:error, any}


  # Private API

  @doc false
  def init({module, pipeline_options}) do
    case module.handle_init(pipeline_options) do
      {:ok, internal_state} ->
        {:ok, %{
          internal_state: internal_state,
        }}

      {:error, reason} ->
        {:stop, reason}
    end
  end


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Pipeline
    end
  end
end
