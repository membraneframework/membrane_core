defmodule Membrane.Core.Element.PadController do
  alias Membrane.{Core, Event}
  alias Core.{CallbackHandler, PullBuffer}
  alias Core.Element.{EventController, PadModel, State}
  alias Membrane.Element.{Context, Pad}
  require Pad
  use Core.Element.Log
  use Membrane.Helper

  def init_pads(%State{module: module} = state) do
    with {:ok, parsed_src_pads} <- handle_known_pads(:known_source_pads, :source, module),
         {:ok, parsed_sink_pads} <- handle_known_pads(:known_sink_pads, :sink, module) do
      pads = %{
        data: %{},
        info: Map.merge(parsed_src_pads, parsed_sink_pads),
        dynamic_currently_linking: []
      }

      {:ok, %State{state | pads: pads}}
    else
      {:error, reason} -> warn_error("Error parsing pads", reason, state)
    end
  end

  defp handle_known_pads(known_pads_fun, direction, module) do
    known_pads =
      cond do
        function_exported?(module, known_pads_fun, 0) ->
          apply(module, known_pads_fun, [])

        true ->
          %{}
      end

    known_pads
    |> Helper.Enum.flat_map_with(fn params -> parse_pad(params, direction) end)
    ~>> ({:ok, parsed_pads} -> {:ok, parsed_pads |> Map.new()})
  end

  def handle_link(pad_name, pad_direction, pid, other_name, props, state) do
    link_pad(
      pad_name,
      pad_direction,
      fn %{direction: dir, mode: mode} = data ->
        data
        |> Map.merge(
          case dir do
            :source -> %{}
            :sink -> %{sticky_messages: []}
          end
        )
        |> Map.merge(
          case {dir, mode} do
            {:sink, :pull} ->
              :ok =
                pid
                |> GenServer.call({:membrane_demand_in, [data.options.demand_in, other_name]})

              pb =
                PullBuffer.new(
                  state.name,
                  {pid, other_name},
                  pad_name,
                  data.options.demand_in,
                  props[:pull_buffer] || %{}
                )

              {:ok, pb} = pb |> PullBuffer.fill()
              %{buffer: pb, self_demand: 0}

            {:source, :pull} ->
              %{demand: 0}

            {_, :push} ->
              %{}
          end
        )
        |> Map.merge(%{name: pad_name, pid: pid, other_name: other_name})
      end,
      state
    )
  end

  def handle_linking_finished(state) do
    with {:ok, state} <-
           state.pads.dynamic_currently_linking
           |> Helper.Enum.reduce_with(state, &handle_pad_added/2) do
      static_unlinked =
        state.pads.info
        |> Map.values()
        |> Enum.filter(&(!&1.is_dynamic))
        |> Enum.map(& &1.name)

      if(static_unlinked |> Enum.empty?() |> Kernel.!()) do
        warn(
          """
          Some static pads remained unlinked: #{inspect(static_unlinked)}
          """,
          state
        )
      end

      {:ok, clear_currently_linking(state)}
    end
  end

  def handle_unlink(pad_name, state) do
    with {:ok, state} <-
           PadModel.get_data(pad_name, %{direction: :sink}, state)
           |> (case do
                 {:ok, %{eos: false}} ->
                   EventController.handle_event(
                     pad_name,
                     %{Event.eos() | payload: :auto_eos, mode: :async},
                     state
                   )

                 _ ->
                   {:ok, state}
               end),
         {:ok, state} <- handle_pad_removed(pad_name, state),
         {:ok, state} <- PadModel.delete_data(pad_name, state) do
      {:ok, state}
    end
  end

  def get_pad_full_name(pad_name, state) do
    {full_name, state} =
      state
      |> Helper.Struct.get_and_update_in([:pads, :info, pad_name], fn
        nil ->
          :pop

        %{is_dynamic: true, current_id: id} = pad_info ->
          {{:dynamic, pad_name, id}, %{pad_info | current_id: id + 1}}

        %{is_dynamic: false} = pad_info ->
          {pad_name, pad_info}
      end)

    {full_name |> Helper.wrap_nil(:unknown_pad), state}
  end

  defp link_pad({:dynamic, name, _no} = full_name, direction, init_f, state) do
    with %{direction: ^direction, is_dynamic: true} = data <- state.pads.info[name] do
      {:ok, state} = init_pad_data(full_name, data, init_f, state)
      state = add_to_currently_linking(full_name, state)
      {:ok, state}
    else
      %{direction: actual_direction} ->
        {:error, {:invalid_pad_direction, [expected: direction, actual: actual_direction]}}

      %{is_dynamic: false} ->
        {:error, :not_dynamic_pad}

      nil ->
        {:error, :unknown_pad}
    end
  end

  defp link_pad(name, direction, init_f, state) do
    with %{direction: ^direction, is_dynamic: false} = data <- state.pads.info[name] do
      state = state |> Helper.Struct.update_in([:pads, :info], &(&1 |> Map.delete(name)))
      init_pad_data(name, data, init_f, state)
    else
      %{direction: actual_direction} ->
        {:error, {:invalid_pad_direction, [expected: direction, actual: actual_direction]}}

      %{is_dynamic: true} ->
        {:error, :not_static_pad}

      nil ->
        case PadModel.get_data(direction, %{direction: name}, state) do
          {:ok, _} -> {:error, :already_linked}
          _ -> {:error, :unknown_pad}
        end
    end
  end

  defp init_pad_data(name, params, init_f, state) do
    params =
      params
      |> Map.merge(%{name: name, pid: nil, caps: nil, other_name: nil, sos: false, eos: false})
      |> init_f.()

    {:ok, state |> Helper.Struct.put_in([:pads, :data, name], params)}
  end

  defp add_to_currently_linking(name, state),
    do: state |> Helper.Struct.update_in([:pads, :dynamic_currently_linking], &[name | &1])

  defp clear_currently_linking(state),
    do: state |> Helper.Struct.put_in([:pads, :dynamic_currently_linking], [])

  defp parse_pad({name, {availability, :push, caps}}, direction)
       when is_atom(name) and Pad.is_availability(availability) do
    do_parse_pad(name, availability, :push, caps, direction)
  end

  defp parse_pad({name, {availability, :pull, caps}}, :source)
       when is_atom(name) and Pad.is_availability(availability) do
    do_parse_pad(name, availability, :pull, caps, :source, %{other_demand_in: nil})
  end

  defp parse_pad({name, {availability, {:pull, demand_in: demand_in}, caps}}, :sink)
       when is_atom(name) and Pad.is_availability(availability) do
    do_parse_pad(name, availability, :pull, caps, :sink, %{demand_in: demand_in})
  end

  defp parse_pad(params, direction),
    do: {:error, {:invalid_pad_config, params, direction: direction}}

  defp do_parse_pad(name, availability, mode, caps, direction, options \\ %{}) do
    parsed_pad =
      %{
        name: name,
        mode: mode,
        direction: direction,
        accepted_caps: caps,
        availability: availability,
        options: options
      }
      |> Map.merge(
        if availability |> Pad.availability_mode() == :dynamic do
          %{current_id: 0, is_dynamic: true}
        else
          %{is_dynamic: false}
        end
      )

    {:ok, [{name, parsed_pad}]}
  end

  defp handle_pad_added(name, state) do
    context = %Context.PadAdded{
      direction: PadModel.get_data!(name, :direction, state)
    }

    CallbackHandler.exec_and_handle_callback(
      :handle_pad_added,
      ActionHandler,
      [name, context],
      state
    )
  end

  defp handle_pad_removed(name, state) do
    %{caps: caps, direction: direction} = PadModel.get_data!(name, %{}, state)
    context = %Context.PadRemoved{direction: direction, caps: caps}

    CallbackHandler.exec_and_handle_callback(
      :handle_pad_removed,
      ActionHandler,
      [name, context],
      state
    )
  end
end
