defmodule Membrane.Core.Element.FlowControlUtils do
  @moduledoc false

  alias Membrane.Core.Element.State

  require Membrane.Core.Child.PadModel, as: PadModel
  require Membrane.Core.Message, as: Message
  require Membrane.Pad, as: Pad

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

  # do handle_link dorzuć wynik output_pad_flow_control()
  # na wiadomosc :output_pad_flow_control, ...,  dostaną na auto pada wywolaj handle_opposite_endpoint_flow_control()
  # na dodanie input auto pada wywolaj handle_input_auto_pad_added()
  # na handle_playing wywolaj resolve...()

  @spec pad_effective_flow_control(Pad.ref(), State.t()) :: :push | :pull | :undefined
  def pad_effective_flow_control(pad_ref, state) do
    pad_name = Pad.name_by_ref(pad_ref)

    state.pads_info
    |> get_in([pad_name, :flow_control])
    |> case do
      :manual -> :pull
      :push -> :push
      :auto -> state.auto_pads_flow_control
    end
  end

  @spec handle_input_pad_added(Pad.ref(), State.t()) :: State.t()
  def handle_input_pad_added(pad_ref, state) do
    with %{pads_data: %{^pad_ref => %{flow_control: :auto} = pad_data}} <- state do
      handle_opposite_endpoint_flow_control(
        pad_ref,
        pad_data.opposite_endpoint_flow_control,
        state
      )
    end
  end

  @spec handle_opposite_endpoint_flow_control(
          Pad.ref(),
          :push | :pull | :undefined,
          State.t()
        ) ::
          State.t()
  def handle_opposite_endpoint_flow_control(
        my_pad_ref,
        opposite_endpoint_flow_control,
        state
      ) do
    pad_data = PadModel.get_data!(state, my_pad_ref)

    if pad_data.direction != :input do
      raise "this function should be called only for input pads"
    end

    pad_data = %{pad_data | opposite_endpoint_flow_control: opposite_endpoint_flow_control}
    state = PadModel.set_data!(state, my_pad_ref, pad_data)

    cond do
      pad_data.flow_control != :auto or opposite_endpoint_flow_control == :undefined or
          state.playback == :stopped ->
        state

      state.auto_pads_flow_control == :undefined ->
        resolve_auto_pads_flow_control(state)

      state.auto_pads_flow_control == :push and opposite_endpoint_flow_control == :pull ->
        raise "dupa dupa 123"

      state.auto_pads_flow_control == :pull or opposite_endpoint_flow_control == :push ->
        state
    end
  end

  @spec resolve_auto_pads_flow_control(State.t()) :: State.t()
  def resolve_auto_pads_flow_control(state) do
    input_auto_pads =
      Map.values(state.pads_data)
      |> Enum.filter(&(&1.direction == :input && &1.flow_control == :auto))

    auto_pads_flow_control =
      input_auto_pads
      |> Enum.group_by(& &1.opposite_endpoint_flow_control)
      |> case do
        %{pull: _pads} -> :pull
        %{push: _pads} -> :push
        %{} -> :undefined
      end

    if auto_pads_flow_control != :undefined do
      Enum.each(state.pads_data, fn {_pad_ref, pad_data} ->
        with %{direction: :output, flow_control: :auto} <- pad_data do
          Message.send(pad_data.pid, :opposite_endpoint_flow_control, [
            pad_data.other_ref,
            auto_pads_flow_control
          ])
        end
      end)
    end

    %{state | auto_pads_flow_control: auto_pads_flow_control}
  end
end
