defmodule Membrane.Core.Element.DiamondDetectionController do
  @moduledoc false

  # DESCRIPTION OF THE ALGORITHM OF FINDING DIAMONDS IN THE PIPELINE

  # Definitions:

  # diamond - directed graph that has at least two distinct elements (sink and source) and
  # has two vertex-disjoint paths from the source to the sink.

  # This algorithm takes the directed graph made by all elements within a single pipeline and
  # finds some diamond-subgraphs where all the edges (links) work in the :pull mode,
  # it means in :manual flow control or in :auto flow control if the effective flow control
  # is set to :pull.

  # These diamonds can be dangerous when used with pull flow control, e.g. let's consider
  # a pipeline that contains:
  #   * MP4 demuxer that has two output pads
  #   * MKV muxer that is linked to both of them
  # and let's assume that the MP4 container that is consumed by the MP4 demuxer is unbalanced.
  # If the MKV muxer has pads working in pull mode, then demand on one pad will be satisfied,
  # but on the other won't, because the MP4 container is unbalanced. Then, if MP4 demuxer
  # has pads in auto flow control and its effective flow control is set to :pull, it won't
  # demand on the input, because one of the pads output with :auto flow control doesn't
  # have positive demand, so the whole pipeline will get stuck and won't process more data.

  # The algorithm is made of two phases: (1) triggering and (2) proper searching.

  # (1) Triggering

  # Let's notice that:
  #   * a new diamond can be created only after linking a new spec
  #   * if the new spec caused some new diamond to occur, this diamond will contain some of
  # the links spawned in this spec
  # If the diamond contains a link, it must also contain an element whose output pad
  # is part of this link.

  # After the spec status is set to :done, the parent component that returned the spec will trigger
  # all elements whose output pads have been linked in this spec. The reference of the trigger
  # is always set to the spec reference.

  # If the element is triggered with a specific reference for the first time, it does two
  # things:
  #   * the element forwards the trigger with the same reference via all input pads working
  #     in the pull mode
  #   * if the element has at least two output pads working in the pull mode, it postpones
  #     the proper searching that will be spawned from itself. The time between postponing and the
  #     proper searching is one second. If during this time an element is triggered once
  #     again with a different reference, it won't cause another postponement of the proper
  #     searching, this means that at the time there is at most one proper searching
  #     postponed in the single element

  # (2) Proper searching:

  # Proper searching is started only in elements that have at least two output pads
  # working in the pull mode. When an element starts proper searching, it assigns
  # a new reference to it, different from the reference of the related trigger.

  # When proper searching enters the element (no matter if it is the element that has
  # just started the proper searching, or maybe it was forwarded to it via a link):
  #   * if the element sees the proper searching reference for the first time, then:
  #     - it forwards proper searching via all output pads working in the pull mode
  #     - when proper searching is forwarded, it remembers the path in the graph through
  #       the elements that it has already passed
  #   * if the element has already seen the reference of proper searching, but there is
  #     a repeated element on the path that proper searching traversed to this element,
  #     the element does nothing
  #   * if the element has already seen the reference of proper searching and the traversed
  #     path doesn't contain any repeated elements, it means that the current traversed path
  #     and the path that the proper searching traversed when it entered the element
  #     the previous time together make a diamond. Then, the element logs the found diamond
  #     and doesn't forward proper searching further.

  alias __MODULE__.{DiamondLogger, PathInGraph}
  alias __MODULE__.PathInGraph.Vertex
  alias Membrane.Core.Element.State
  alias Membrane.Element.PadData

  require Membrane.Core.Message, as: Message
  require Membrane.Logger
  require Membrane.Pad, as: Pad

  @component_path_prefix "__membrane_component_path_64_byte_prefix________________________"

  @type diamond_detection_message() :: %{
          :type =>
            :start
            | :start_trigger
            | :diamond_detection
            | :trigger
            | :delete_ref
            | :delete_trigger_ref,
          optional(:ref) => reference(),
          optional(:path) => PathInGraph.t(),
          optional(:pad_ref) => Pad.ref()
        }

  @spec handle_diamond_detection_message(diamond_detection_message(), State.t()) :: State.t()
  def handle_diamond_detection_message(%{type: type} = message, state) do
    case type do
      :start ->
        start_diamond_detection(state)

      :start_trigger ->
        start_diamond_detection_trigger(message.ref, state)

      :diamond_detection ->
        continue_diamond_detection(message.pad_ref, message.ref, message.path, state)

      :trigger ->
        handle_diamond_detection_trigger(message.ref, state)

      :delete_ref ->
        delete_diamond_detection_ref(message.ref, state)

      :delete_trigger_ref ->
        delete_diamond_detection_trigger_ref(message.ref, state)
    end
  end

  @spec start_diamond_detection(State.t()) :: State.t()
  defp start_diamond_detection(state) do
    {component_path, state} = get_component_path(state)

    diamond_detection_path = [
      %PathInGraph.Vertex{pid: self(), component_path: component_path}
    ]

    :ok =
      make_ref()
      |> forward_diamond_detection(diamond_detection_path, state)

    state
  end

  @spec continue_diamond_detection(Pad.ref(), reference(), PathInGraph.t(), State.t()) ::
          State.t()
  defp continue_diamond_detection(
         input_pad_ref,
         diamond_detection_ref,
         diamond_detecton_path,
         state
       ) do
    {component_path, state} = get_component_path(state)

    new_path_vertex = %PathInGraph.Vertex{
      pid: self(),
      component_path: component_path,
      input_pad_ref: input_pad_ref
    }

    diamond_detecton_path = [new_path_vertex | diamond_detecton_path]

    cond do
      not is_map_key(state.diamond_detection.ref_to_path, diamond_detection_ref) ->
        :ok = forward_diamond_detection(diamond_detection_ref, diamond_detecton_path, state)

        :ok =
          %{type: :delete_ref, ref: diamond_detection_ref}
          |> send_after_to_self()

        state
        |> put_in(
          [:diamond_detection, :ref_to_path, diamond_detection_ref],
          diamond_detecton_path
        )

      has_cycle?(diamond_detecton_path) ->
        state

      have_common_prefix?(
        diamond_detecton_path,
        state.diamond_detection.ref_to_path[diamond_detection_ref]
      ) ->
        state

      true ->
        old_diamond_detection_path =
          state.diamond_detection.ref_to_path[diamond_detection_ref]
          |> remove_component_path_prefix()

        :ok =
          diamond_detecton_path
          |> remove_component_path_prefix()
          |> DiamondLogger.log_diamond(old_diamond_detection_path)

        state
    end
  end

  @spec delete_diamond_detection_ref(reference(), State.t()) :: State.t()
  defp delete_diamond_detection_ref(diamond_detection_ref, state) do
    {_path, %State{} = state} =
      state
      |> pop_in([:diamond_detection, :ref_to_path, diamond_detection_ref])

    state
  end

  @spec forward_diamond_detection(reference(), PathInGraph.t(), State.t()) :: :ok
  defp forward_diamond_detection(diamond_detection_ref, diamond_detection_path, state) do
    auto_pull_mode? = state.effective_flow_control == :pull
    [current_entry | diamond_detection_path_tail] = diamond_detection_path

    state.pads_data
    |> Enum.each(fn {pad_ref, pad_data} ->
      if output_pull_pad?(pad_data, auto_pull_mode?) do
        current_entry = %{current_entry | output_pad_ref: pad_ref}
        diamond_detection_path = [current_entry | diamond_detection_path_tail]

        message = %{
          type: :diamond_detection,
          pad_ref: pad_data.other_ref,
          ref: diamond_detection_ref,
          path: diamond_detection_path
        }

        Message.send(pad_data.pid, :diamond_detection, message)
      end
    end)
  end

  defp forward_diamond_detection_trigger(trigger_ref, state) do
    state.pads_data
    |> Enum.each(fn {_pad_ref, %PadData{} = pad_data} ->
      if pad_data.direction == :input and pad_data.flow_control != :push do
        message = %{type: :trigger, ref: trigger_ref}
        Message.send(pad_data.pid, :diamond_detection, message)
      end
    end)
  end

  defp output_pull_pad?(%PadData{} = pad_data, auto_pull_mode?) do
    pad_data.direction == :output and
      (pad_data.flow_control == :manual or
         (pad_data.flow_control == :auto and auto_pull_mode?))
  end

  defp has_cycle?(diamond_detection_path) do
    uniq_length = diamond_detection_path |> Enum.uniq_by(& &1.pid) |> length()
    uniq_length < length(diamond_detection_path)
  end

  @spec start_diamond_detection_trigger(reference(), State.t()) :: State.t()
  defp start_diamond_detection_trigger(spec_ref, state) do
    if map_size(state.pads_data) < 2 or
         MapSet.member?(state.diamond_detection.trigger_refs, spec_ref) do
      state
    else
      do_handle_diamond_detection_trigger(spec_ref, state)
    end
  end

  @spec handle_diamond_detection_trigger(reference(), State.t()) :: State.t()
  defp handle_diamond_detection_trigger(trigger_ref, %State{} = state) do
    if state.type == :endpoint or
         MapSet.member?(state.diamond_detection.trigger_refs, trigger_ref),
       do: state,
       else: do_handle_diamond_detection_trigger(trigger_ref, state)
  end

  defp do_handle_diamond_detection_trigger(trigger_ref, %State{} = state) do
    state =
      state
      |> update_in(
        [:diamond_detection, :trigger_refs],
        &MapSet.put(&1, trigger_ref)
      )

    :ok =
      %{type: :delete_trigger_ref, ref: trigger_ref}
      |> send_after_to_self()

    :ok = forward_diamond_detection_trigger(trigger_ref, state)

    if output_pull_arity(state) >= 2,
      do: postpone_diamond_detection(state),
      else: state
  end

  defp postpone_diamond_detection(%State{} = state) when state.diamond_detection.postponed? do
    state
  end

  defp postpone_diamond_detection(%State{} = state) do
    :ok = %{type: :start} |> send_after_to_self(1)

    state
    |> put_in([:diamond_detection, :postponed?], true)
  end

  @spec delete_diamond_detection_trigger_ref(reference(), State.t()) :: State.t()
  defp delete_diamond_detection_trigger_ref(trigger_ref, state) do
    state
    |> update_in(
      [:diamond_detection, :trigger_refs],
      &MapSet.delete(&1, trigger_ref)
    )
  end

  defp output_pull_arity(state) do
    auto_pull_mode? = state.effective_flow_control == :pull

    state.pads_data
    |> Enum.count(fn {_pad_ref, pad_data} -> output_pull_pad?(pad_data, auto_pull_mode?) end)
  end

  defp send_after_to_self(%{type: _type} = message, seconds \\ 10) do
    send_after_time = Membrane.Time.seconds(seconds) |> Membrane.Time.as_milliseconds(:round)
    message = Message.new(:diamond_detection, message)
    self() |> Process.send_after(message, send_after_time)
    :ok
  end

  defp get_component_path(state) do
    case state.diamond_detection.serialized_component_path do
      nil ->
        # adding @component_path_prefix to component path causes that component path
        # always has more than 64 bytes, so it won't be copied during sending a message

        component_path =
          [@component_path_prefix | Membrane.ComponentPath.get()]
          |> Enum.join()

        state =
          state
          |> put_in(
            [:diamond_detection, :serialized_component_path],
            component_path
          )

        {component_path, state}

      component_path ->
        {component_path, state}
    end
  end

  defp have_common_prefix?(path_a, path_b), do: List.last(path_a) == List.last(path_b)

  defp remove_component_path_prefix(path_in_graph) do
    path_in_graph
    |> Enum.map(fn %Vertex{component_path: @component_path_prefix <> component_path} = vertex ->
      %{vertex | component_path: component_path}
    end)
  end
end
