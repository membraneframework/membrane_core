defmodule Membrane.Core.Element.PadController do
  @moduledoc false

  # Module handling linking and unlinking pads.

  use Bunch
  alias Membrane.{LinkError, Pad}
  alias Membrane.Core.{CallbackHandler, Child, Events, Message, Observability}
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    ActionHandler,
    CallbackContext,
    DemandController,
    EventController,
    FlowControlUtils,
    InputQueue,
    State,
    StreamFormatController,
    Toilet
  }

  alias Membrane.Core.Parent.Link.Endpoint

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Logger
  require Membrane.Pad

  @type link_call_props ::
          %{
            initiator: :parent,
            stream_format_validation_params:
              StreamFormatController.stream_format_validation_params()
          }
          | %{
              initiator: :sibling,
              other_info: PadModel.pad_info() | nil,
              link_metadata: %{toilet: Toilet.t() | nil},
              stream_format_validation_params:
                StreamFormatController.stream_format_validation_params()
            }

  @type link_call_reply_props ::
          {Endpoint.t(), PadModel.pad_info(), %{toilet: Toilet.t() | nil}}

  @type link_call_reply ::
          :ok
          | {:ok, link_call_reply_props}
          | {:error, {:neighbor_dead, reason :: any()}}
          | {:error, {:neighbor_child_dead, reason :: any()}}
          | {:error, {:unknown_pad, name :: Membrane.Child.name(), pad_ref :: Pad.ref()}}

  @default_auto_demand_size_factor 4000

  @doc """
  Verifies linked pad, initializes it's data.
  """
  @spec handle_link(Pad.direction(), Endpoint.t(), Endpoint.t(), link_call_props, State.t()) ::
          {link_call_reply, State.t()}
  def handle_link(direction, endpoint, other_endpoint, link_props, state) do
    Membrane.Logger.debug(
      "Element handle link on pad #{inspect(endpoint.pad_ref)} with pad #{inspect(other_endpoint.pad_ref)} of child #{inspect(other_endpoint.child)}"
    )

    name = endpoint.pad_ref |> Pad.name_by_ref()

    info =
      case Map.fetch(state.pads_info, name) do
        {:ok, info} ->
          info

        :error ->
          raise LinkError,
                "Tried to link via unknown pad #{inspect(name)} of #{inspect(state.name)}"
      end

    :ok = Child.PadController.validate_pad_being_linked!(direction, info)

    do_handle_link(endpoint, other_endpoint, info, link_props, state)
  end

  defp do_handle_link(
         endpoint,
         other_endpoint,
         info,
         %{initiator: :parent} = props,
         state
       ) do
    flow_control = FlowControlUtils.pad_effective_flow_control(endpoint.pad_ref, state)

    handle_link_response =
      Message.call(other_endpoint.pid, :handle_link, [
        Pad.opposite_direction(info.direction),
        other_endpoint,
        endpoint,
        %{
          initiator: :sibling,
          other_info: info,
          link_metadata: %{
            observability_metadata: Observability.setup_link(endpoint.pad_ref)
          },
          stream_format_validation_params: [],
          opposite_endpoint_flow_control: flow_control
        }
        # |> IO.inspect(label: "link_props to sibling")
      ])

    case handle_link_response do
      {:ok, {other_endpoint, other_info, link_metadata}} ->
        :ok =
          Child.PadController.validate_pad_mode!(
            {endpoint.pad_ref, info},
            {other_endpoint.pad_ref, other_info}
          )

        state =
          init_pad_data(
            endpoint,
            other_endpoint,
            info,
            props.stream_format_validation_params,
            :undefined,
            other_info,
            link_metadata,
            state
          )

        state = maybe_handle_pad_added(endpoint.pad_ref, state)
        {:ok, state}

      {:error, {:call_failure, reason}} ->
        Membrane.Logger.debug("""
        Tried to link pad #{inspect(endpoint.pad_ref)}, but neighbour #{inspect(other_endpoint.child)}
        is not alive.
        """)

        {{:error, {:neighbor_dead, reason}}, state}

      {:error, {:unknown_pad, _name, _pad_ref}} = error ->
        {error, state}

      {:error, {:child_dead, reason}} ->
        {{:error, {:neighbor_child_dead, reason}}, state}
    end
  end

  defp do_handle_link(
         endpoint,
         other_endpoint,
         info,
         %{initiator: :sibling} = link_props,
         state
       ) do
    # dupa: check if auto_push?: true and sibling is in pull mode
    # jak jestes filtrem:

    # Jak przychodzi input pad
    # if auto_push? do
    # jezeli przychodzi link w pushu, to czilera utopia
    # jezeli przychodzi link w pullu, to wyslij wiadomosc zeby zamienil w auto_push. sourcy powinny raisowac na takie cos

    # if not auto_push? do
    # jezeli przychodzi link w pullu, to nic nie rob
    # jezeli przychodzi w pushu, a są juz inne w pullu, to nic nie rob i ustaw toilet
    # jezeli przychodzi w pushu, i jest jedynym linkiem aktualnie, to zamien sie w auto_push i wyslij wiadomosc na output pady

    # Jak przychodzi output pad
    # if auto_push, to wysylasz wiadomosc ze jestes pushem
    # jak nie, to nic nie robisz

    # raisowanie powinno odbywac sie w handle_playing, lub podczas linkowania po handle_playing
    # istnieją filtry w autodemandach, ktore mają flage true, i takie ktore nie
    # co zrobic zeby dostac flage w true: miec wszystkie pady inputy w pushu

    # powinno byc tak:
    # wczesniej mi sie mieszalo przez te maszynke xd
    # teraz robimy wersje konserwatywną: tzn zamieniamy tylko fitry autodemandowe
    # raisujemy na probe dolaczenia pull sourcea do auto pusha: potem moze doimpementujemy w 2 strone
    # na poczatku stawiamy rzeczy i one se dzialaja w autodemandach
    # source pushowy / pullowy wysyla na dzien dobry padem info jaki ma typ pada
    # filter ktory ma za sobą jakis source pullowy, wysyla info ze jest pullowy
    # filter ktory ma za sobą wszystkie source pushowe, wysyla info ze jest pushowy

    # na dzien dobry filter w auto dziala na autodemandach
    # jak zapnie mu sie source, to mu wysyla info jakiego jest typu
    # jak wszystkie source są pullowe, to nic sie nie zmienia
    # raisowac mamy, jak source pullowy dopnie sie do auto pusha

    # ogolnie auto element moze byc w 3 stanach:
    # nie wie jeszcze jaki source jest przed nim -> auto demand A
    # wie ze ma przed sobą pull source -> auto demand B
    # wue ze ma przed sobą same pushowe source -> auto push C
    # narazie sie wywalajmy przy probie przejscia z auto-push w auto-demand (jakiejkolwiek)
    # mozna przejsc ze stany A do B lub z A do C
    # pad sourcea jest zawsze w stanie B lub C
    # jak filter jest w B lub C, to jest output pady same sie takie staja
    # jezeli masz jakiegos przodka w B, to sam jestes w B
    # jezeli nie masz nikogo w B a masz kogos w C, to sam jestes w C
    # jak wchodzisz do B albo C, albo juz jestes ale dodaje ci sie nowy output pad, to wysylasz nim info ze jestes B lub C
    # jak przechodzisz z A do C to masz w dupie demandy
    # jak przechodzisz z A do B, to ignorujesz potem info o tym ze ktos dolaczyl a jest w C

    # mozna zrobic pole auto_mode: :push / :pull / :undefined

    # czyli tak:
    # jezeli wiemy jaki jest mode pada, to wysylamy to w handle_link, w przeciwnym razie jak sie dowiemy
    # manual/push output pad jest zawsze w pull/push mode
    # jak mamy auto pada, to dziedziczy po typie elementu, jezeli nie jest on :undefined
    # jak jest, to jak element wyjdzie z :undefined, to wtedy wysyla poprawną wiadomosc na output pady

    # algo wiadomosci z wlasnym trybem

    # USTALANIE:
    # - trigerrowane na handle_playing lub na przyjscie trybu pada, gdy jestesmy po playing
    # - z undefined, gdy jest jakis przodek w pull, to jestem w pull
    # - z undefined, gdy wszyscy przodkowie sa w push, to jestem w push
    # - z undefined, gdy nie ma nic, to czekam dalej
    # - z nie undefined, sprawdzam czy sie zgadza, jak sie cos nie zgadza to sie wywalam (jak bylem w pull, to czilera utopia, jak bylem w push, to nie da ise przejsc juz do pull i raisuje)

    # WYSYLANIE:
    # - tylko po output padach
    # - gdy jest ustalone, to w handle_link. Gdy na handle_link jest niestualone, to tylko jak zostanie ustalone

    # ODBIERANIE:
    # - po input padach
    # - w handle_link lub w specjalnej wiadomosci
    # - gdy jestesmy przed handle_playing, to tylko zapisz
    # - na handle_playing podejmij decyzje
    # - gdy dstajesz mode po handle_playing, to jesli nie podjales decyzji to ja podejmij, a jesli ja juz kiedys podjales, to zwaliduj czy sie nie wywalic

    # zatem operacje jakie chce miec w nowym module:
    # dodaj pad effective flow control
    # handle playing
    # hanlde pad added (output)

    %{
      other_info: other_info,
      link_metadata: link_metadata,
      stream_format_validation_params: stream_format_validation_params,
      opposite_endpoint_flow_control: opposite_endpoint_flow_control
    } = link_props

    # |> IO.inspect(label: "link_props from sibling")

    {output_info, input_info, input_endpoint} =
      if info.direction == :output,
        do: {info, other_info, other_endpoint},
        else: {other_info, info, endpoint}

    {output_demand_unit, input_demand_unit} = resolve_demand_units(output_info, input_info)

    link_metadata =
      Map.put(link_metadata, :input_demand_unit, input_demand_unit)
      |> Map.put(:output_demand_unit, output_demand_unit)

    toilet =
      if input_demand_unit != nil,
        do:
          Toilet.new(
            input_endpoint.pad_props.toilet_capacity,
            input_demand_unit,
            self(),
            input_endpoint.pad_props.throttling_factor
          )

    Observability.setup_link(endpoint.pad_ref, link_metadata.observability_metadata)
    link_metadata = Map.put(link_metadata, :toilet, toilet)

    :ok =
      Child.PadController.validate_pad_mode!(
        {endpoint.pad_ref, info},
        {other_endpoint.pad_ref, other_info}
      )

    state =
      init_pad_data(
        endpoint,
        other_endpoint,
        info,
        stream_format_validation_params,
        opposite_endpoint_flow_control,
        other_info,
        link_metadata,
        state
      )

    state = FlowControlUtils.handle_input_pad_added(endpoint.pad_ref, state)
    state = maybe_handle_pad_added(endpoint.pad_ref, state)
    {{:ok, {endpoint, info, link_metadata}}, state}
  end

  @doc """
  Handles situation where pad has been unlinked (e.g. when connected element has been removed from pipeline)

  Removes pad data.
  Signals an EoS (via handle_event) to the element if unlinked pad was an input.
  Executes `handle_pad_removed` callback if the pad was dynamic.
  Note: it also flushes all buffers from PlaybackBuffer.
  """
  @spec handle_unlink(Pad.ref(), State.t()) :: State.t()
  def handle_unlink(pad_ref, state) do
    with {:ok, %{availability: :on_request}} <- PadModel.get_data(state, pad_ref) do
      state = generate_eos_if_needed(pad_ref, state)
      state = maybe_handle_pad_removed(pad_ref, state)
      state = remove_pad_associations(pad_ref, state)
      PadModel.delete_data!(state, pad_ref)
    else
      {:ok, %{availability: :always}} when state.terminating? ->
        state

      {:ok, %{availability: :always}} ->
        raise Membrane.PadError,
              "Tried to unlink a static pad #{inspect(pad_ref)}. Static pads cannot be unlinked unless element is terminating"

      {:error, :unknown_pad} ->
        with false <- state.terminating?,
             %{availability: :always} <- state.pads_info[Pad.name_by_ref(pad_ref)] do
          raise Membrane.PadError,
                "Tried to unlink a static pad #{inspect(pad_ref)}, before it was linked. Static pads cannot be unlinked unless element is terminating"
        end

        Membrane.Logger.debug(
          "Ignoring unlinking pad #{inspect(pad_ref)} that hasn't been successfully linked"
        )

        state
    end
  end

  defp resolve_demand_units(output_info, input_info) do
    output_demand_unit =
      if output_info[:flow_control] == :push,
        do: nil,
        else: output_info[:demand_unit] || input_info[:demand_unit] || :buffers

    input_demand_unit =
      if input_info[:flow_control] == :push,
        do: nil,
        else: input_info[:demand_unit] || output_info[:demand_unit] || :buffers

    {output_demand_unit, input_demand_unit}
  end

  defp init_pad_data(
         endpoint,
         other_endpoint,
         info,
         stream_format_validation_params,
         opposite_endpoint_flow_control,
         other_info,
         metadata,
         state
       ) do
    data =
      info
      |> Map.delete(:accepted_formats_str)
      |> Map.merge(%{
        pid: other_endpoint.pid,
        other_ref: other_endpoint.pad_ref,
        options:
          Child.PadController.parse_pad_options!(info.name, endpoint.pad_props.options, state),
        ref: endpoint.pad_ref,
        stream_format_validation_params: stream_format_validation_params,
        opposite_endpoint_flow_control: opposite_endpoint_flow_control,
        stream_format: nil,
        start_of_stream?: false,
        end_of_stream?: false,
        associated_pads: []
      })

    data = data |> Map.merge(init_pad_direction_data(data, endpoint.pad_props, metadata, state))

    data =
      data |> Map.merge(init_pad_mode_data(data, endpoint.pad_props, other_info, metadata, state))

    data = struct!(Membrane.Element.PadData, data)
    state = put_in(state, [:pads_data, endpoint.pad_ref], data)

    if data.flow_control == :auto do
      state =
        state.pads_data
        |> Map.values()
        |> Enum.filter(&(&1.direction != data.direction and &1.flow_control == :auto))
        |> Enum.reduce(state, fn other_data, state ->
          PadModel.update_data!(state, other_data.ref, :associated_pads, &[data.ref | &1])
        end)

      case data.direction do
        :input -> DemandController.send_auto_demand_if_needed(endpoint.pad_ref, state)
        :output -> state
      end
    else
      state
    end
  end

  defp init_pad_direction_data(%{direction: :input}, _props, metadata, _state),
    do: %{
      sticky_messages: [],
      demand_unit: metadata.input_demand_unit,
      other_demand_unit: metadata.output_demand_unit
    }

  defp init_pad_direction_data(%{direction: :output}, _props, metadata, _state),
    do: %{demand_unit: metadata.output_demand_unit, other_demand_unit: metadata.input_demand_unit}

  defp init_pad_mode_data(
         %{direction: :input, flow_control: :manual} = data,
         props,
         other_info,
         metadata,
         %State{}
       ) do
    %{ref: ref, pid: pid, other_ref: other_ref, demand_unit: this_demand_unit} = data

    enable_toilet? = other_info.flow_control == :push

    input_queue =
      InputQueue.init(%{
        inbound_demand_unit: other_info[:demand_unit] || this_demand_unit,
        outbound_demand_unit: this_demand_unit,
        demand_pid: pid,
        demand_pad: other_ref,
        log_tag: inspect(ref),
        toilet?: enable_toilet?,
        target_size: props.target_queue_size,
        min_demand_factor: props.min_demand_factor
      })

    %{input_queue: input_queue, demand: 0, toilet: if(enable_toilet?, do: metadata.toilet)}
  end

  defp init_pad_mode_data(
         %{direction: :output, flow_control: :manual},
         _props,
         _other_info,
         _metadata,
         _state
       ) do
    %{demand: 0}
  end

  defp init_pad_mode_data(
         %{flow_control: :auto, direction: direction},
         props,
         other_info,
         metadata,
         %State{} = state
       ) do
    associated_pads =
      state.pads_data
      |> Map.values()
      |> Enum.filter(&(&1.direction != direction and &1.flow_control == :auto))
      |> Enum.map(& &1.ref)

    toilet =
      if direction == :input and other_info.flow_control == :push do
        metadata.toilet
      else
        nil
      end

    auto_demand_size =
      if direction == :input do
        props.auto_demand_size ||
          Membrane.Buffer.Metric.Count.buffer_size_approximation() *
            @default_auto_demand_size_factor
      else
        nil
      end

    %{
      demand: 0,
      associated_pads: associated_pads,
      auto_demand_size: auto_demand_size,
      toilet: toilet
    }
  end

  defp init_pad_mode_data(
         %{flow_control: :push, direction: :output},
         _props,
         %{flow_control: other_flow_control},
         metadata,
         _state
       )
       when other_flow_control in [:auto, :manual] do
    %{toilet: metadata.toilet}
  end

  defp init_pad_mode_data(_data, _props, _other_info, _metadata, _state), do: %{}

  @doc """
  Generates end of stream on the given input pad if it hasn't been generated yet
  and playback is `playing`.
  """
  @spec generate_eos_if_needed(Pad.ref(), State.t()) :: State.t()
  def generate_eos_if_needed(pad_ref, state) do
    %{direction: direction, end_of_stream?: eos?} = PadModel.get_data!(state, pad_ref)

    if direction == :input and not eos? and state.playback == :playing do
      EventController.exec_handle_event(pad_ref, %Events.EndOfStream{}, state)
    else
      state
    end
  end

  @doc """
  Removes all associations between the given pad and any other_endpoint pads.
  """
  @spec remove_pad_associations(Pad.ref(), State.t()) :: State.t()
  def remove_pad_associations(pad_ref, state) do
    case PadModel.get_data!(state, pad_ref) do
      %{flow_control: :auto} = pad_data ->
        state =
          Enum.reduce(pad_data.associated_pads, state, fn pad, state ->
            PadModel.update_data!(state, pad, :associated_pads, &List.delete(&1, pad_data.ref))
          end)
          |> PadModel.set_data!(pad_ref, :associated_pads, [])

        if pad_data.direction == :output do
          Enum.reduce(
            pad_data.associated_pads,
            state,
            &DemandController.send_auto_demand_if_needed/2
          )
        else
          state
        end

      _pad_data ->
        state
    end
  end

  @spec maybe_handle_pad_added(Pad.ref(), State.t()) :: State.t()
  defp maybe_handle_pad_added(ref, state) do
    %{options: pad_opts, availability: availability} = PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      context = &CallbackContext.from_state(&1, pad_options: pad_opts)

      CallbackHandler.exec_and_handle_callback(
        :handle_pad_added,
        ActionHandler,
        %{context: context},
        [ref],
        state
      )
    else
      state
    end
  end

  @spec maybe_handle_pad_removed(Pad.ref(), State.t()) :: State.t()
  defp maybe_handle_pad_removed(ref, state) do
    %{availability: availability} = PadModel.get_data!(state, ref)

    if Pad.availability_mode(availability) == :dynamic do
      CallbackHandler.exec_and_handle_callback(
        :handle_pad_removed,
        ActionHandler,
        %{context: &CallbackContext.from_state/1},
        [ref],
        state
      )
    else
      state
    end
  end
end
