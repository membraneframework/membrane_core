defmodule Membrane.Core.BinTest do
  use ExUnit.Case, async: true

  alias Membrane.Bin
  alias Membrane.Testing

  import Membrane.Testing.Assertions

  defmodule TestBin do
    use Membrane.Bin

    def_options filter1: [type: :atom],
                filter2: [type: :atom]

    def_input_pad :input, demand_unit: :buffers, caps: :any

    def_output_pad :output, caps: :any

    @impl true
    def handle_init(opts) do
      children = [
        filter1: opts.filter1,
        filter2: opts.filter1
      ]

      links = %{
        # `this_bin` is a macro from `use Membrane.Bin`
        {this_bin(), :input} => {:filter1, :input, buffer: [preferred_size: 10]},
        {:filter1, :output} => {:filter2, :input, buffer: [preferred_size: 10]},
        {:filter2, :output} => {this_bin(), :output, buffer: [preferred_size: 10]}
      }

      spec = %Membrane.Bin.Spec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec}, state}
    end

    def handle_spec_started(elements, state) do
      {:ok, state}
    end
  end

  defmodule TestFilter do
    alias Membrane.Event.StartOfStream

    use Membrane.Filter

    def_output_pad :output, caps: :any

    def_input_pad :input, demand_unit: :buffers, caps: :any

    def_options demand_generator: [
                  type: :function,
                  spec: (pos_integer -> non_neg_integer),
                  default: &__MODULE__.default_demand_generator/1
                ],
                target: [type: :pid],
                playing_delay: [type: :integer, default: 0],
                ref: [type: :any, default: nil],
                sof_sent?: [type: :boolean, default: false]

    @impl true
    def handle_init(%{target: t, ref: ref} = opts) do
      send(t, {:filter_pid, ref, self()})
      {:ok, Map.put(opts, :pads, MapSet.new())}
    end

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      new_pads = MapSet.put(state.pads, pad)
      {:ok, %{state | pads: new_pads}}
    end

    @impl true
    def handle_pad_removed(pad, _ctx, state) do
      new_pads = MapSet.delete(state.pads, pad)
      {:ok, %{state | pads: new_pads}}
    end

    @impl true
    def handle_prepared_to_playing(_ctx, %{playing_delay: 0} = state) do
      send(state.target, {:playing, self()})
      {:ok, state}
    end

    def handle_prepared_to_playing(_ctx, %{playing_delay: time} = state) do
      Process.send_after(self(), :resume_after_wait, time)
      {{:ok, playback_change: :suspend}, state}
    end

    @impl true
    def handle_other(:resume_after_wait, _ctx, state) do
      {{:ok, playback_change: :resume}, state}
    end

    @impl true
    def handle_demand(:output, size, _, _ctx, state) do
      demands =
        state.pads
        |> Enum.map(fn pad -> {:demand, {pad, state.demand_generator.(size)}} end)

      {{:ok, demands}, state}
    end

    @impl true
    def handle_process(_pad, buf, _, state) do
      {{:ok, buffer: {:output, buf}}, state}
    end

    @impl true
    def handle_event(_pad, %StartOfStream{} = ev, _ctx, %{sof_sent?: false} = state) do
      {{:ok, forward: ev}, %{state | sof_sent?: true}}
    end

    def handle_event(_pad, %StartOfStream{}, _ctx, %{sof_sent?: true} = state) do
      {:ok, state}
    end

    def handle_event(_pad, event, _ctx, state) do
      {{:ok, forward: event}, state}
    end

    @impl true
    def handle_shutdown(%{target: pid}) do
      send(pid, {:element_shutting_down, self()})
      :ok
    end

    def default_demand_generator(demand), do: demand
  end

  test "Bin starts in pipeline and transmits buffers successfully" do
    buffers = ['a', 'b', 'c']

    {:ok, pipeline} =
      Testing.Pipeline.start_link(%Testing.Pipeline.Options{
        elements: [
          source: %Testing.Source{output: buffers},
          test_bin: %TestBin{
            filter1: %TestFilter{target: self()},
            filter2: %TestFilter{target: self()}
          },
          sink: Testing.Sink
        ]
      })

    buffers
    |> Enum.each(fn b -> assert_sink_buffer(pipeline, :sink, ^b) end)
  end
end
