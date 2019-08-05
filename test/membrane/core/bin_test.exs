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
        filter2: opts.filter2
      ]

      links = %{
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

    def handle_stopped_to_prepared(state), do: {:ok, state}

    def handle_prepared_to_playing(state), do: {:ok, state}

    def handle_notification(msg, _ctx, state), do: {{:ok, notify: msg}, state}
  end

  defmodule TestSinkBin do
    use Membrane.Bin

    def_options filter: [type: :atom],
                sink: [type: :atom]

    def_input_pad :input, demand_unit: :buffers, caps: :any

    @impl true
    def handle_init(opts) do
      children = [
        filter: opts.filter,
        sink: opts.sink
      ]

      links = %{
        {this_bin(), :input} => {:filter, :input, buffer: [preferred_size: 10]},
        {:filter, :output} => {:sink, :input, buffer: [preferred_size: 10]}
      }

      spec = %Membrane.Bin.Spec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec}, state}
    end

    def handle_spec_started(elements, state), do: {:ok, state}

    def handle_stopped_to_prepared(state), do: {:ok, state}

    def handle_prepared_to_playing(state), do: {:ok, state}

    def handle_notification(msg, _ctx, state), do: {{:ok, notify: msg}, state}
  end

  defmodule TestPadlessBin do
    use Membrane.Bin

    def_options source: [type: :atom],
                sink: [type: :atom]

    @impl true
    def handle_init(opts) do
      children = [
        source: opts.source,
        sink: opts.sink
      ]

      links = %{
        {:source, :output} => {:sink, :input, buffer: [preferred_size: 10]}
      }

      spec = %Membrane.Bin.Spec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec}, state}
    end

    def handle_spec_started(elements, state), do: {:ok, state}

    def handle_stopped_to_prepared(state), do: {:ok, state}

    def handle_prepared_to_playing(state), do: {:ok, state}

    def handle_notification(msg, _ctx, state), do: {{:ok, notify: msg}, state}
  end

  defmodule TestFilter do
    alias Membrane.Event.StartOfStream

    use Membrane.Filter

    def_output_pad :output, caps: :any

    def_input_pad :input, demand_unit: :buffers, caps: :any

    @impl true
    def handle_init(opts), do: {:ok, opts}

    @impl true
    def handle_other({:notify_parent, notif}, _ctx, state), do: {{:ok, notify: notif}, state}

    @impl true
    def handle_prepared_to_playing(_ctx, state), do: {:ok, state}

    @impl true
    def handle_demand(:output, size, _, _ctx, state), do: {{:ok, demand: {:input, size}}, state}

    @impl true
    def handle_process(_pad, buf, _, state), do: {{:ok, buffer: {:output, buf}}, state}

    @impl true
    def handle_event(_pad, event, _ctx, state), do: {{:ok, forward: event}, state}

    @impl true
    def handle_shutdown(_), do: :ok
  end

  describe "Starting and transmitting buffers" do
    test "in simple, flat use case" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: %Testing.Source{output: buffers},
            test_bin: %TestBin{
              filter1: TestFilter,
              filter2: TestFilter
            },
            sink: Testing.Sink
          ]
        })

      Testing.Pipeline.play(pipeline) == :ok

      assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
      assert_pipeline_playback_changed(pipeline, :prepared, :playing)

      assert_start_of_stream(pipeline, :sink)

      buffers
      |> Enum.each(fn b -> assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^b}) end)

      assert_end_of_stream(pipeline, :sink)
    end

    test "when bin is next to a bin" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: %Testing.Source{output: buffers},
            test_bin1: %TestBin{
              filter1: TestFilter,
              filter2: TestFilter
            },
            test_bin2: %TestBin{
              filter1: TestFilter,
              filter2: TestFilter
            },
            sink: Testing.Sink
          ]
        })

      Testing.Pipeline.play(pipeline) == :ok

      assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
      assert_pipeline_playback_changed(pipeline, :prepared, :playing)

      assert_start_of_stream(pipeline, :sink)

      buffers
      |> Enum.each(fn b -> assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^b}) end)

      assert_end_of_stream(pipeline, :sink)
    end

    test "when bins are nested" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: %Testing.Source{output: buffers},
            test_bin: %TestBin{
              filter1: TestFilter,
              filter2: %TestBin{
                filter1: TestFilter,
                filter2: TestFilter
              }
            },
            sink: Testing.Sink
          ]
        })

      Testing.Pipeline.play(pipeline) == :ok

      assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
      assert_pipeline_playback_changed(pipeline, :prepared, :playing)

      assert_start_of_stream(pipeline, :sink)

      buffers
      |> Enum.each(fn b -> assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^b}) end)

      assert_end_of_stream(pipeline, :sink)
    end

    test "when there are consecutive bins that are nested" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: %Testing.Source{output: buffers},
            test_bin: %TestBin{
              filter1: %TestBin{
                filter1: TestFilter,
                filter2: TestFilter
              },
              filter2: %TestBin{
                filter1: TestFilter,
                filter2: TestFilter
              }
            },
            sink: Testing.Sink
          ]
        })

      Testing.Pipeline.play(pipeline) == :ok

      assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
      assert_pipeline_playback_changed(pipeline, :prepared, :playing)

      assert_start_of_stream(pipeline, :sink)

      buffers
      |> Enum.each(fn b -> assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: ^b}) end)

      assert_end_of_stream(pipeline, :sink)
    end

    test "when pipeline has only one element being a padless bin" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            test_bin: %TestPadlessBin{
              source: %Testing.Source{output: buffers},
              sink: Testing.Sink
            }
          ]
        })

      Testing.Pipeline.play(pipeline) == :ok

      assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
      assert_pipeline_playback_changed(pipeline, :prepared, :playing)

      assert_start_of_stream(pipeline, :test_bin)

      buffers
      |> Enum.each(fn b ->
        assert_sink_buffer(pipeline, :test_bin, %Membrane.Buffer{payload: ^b})
      end)

      assert_end_of_stream(pipeline, :test_bin)
    end

    test "when bin is a sink bin" do
      buffers = ['a', 'b', 'c']

      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: %Testing.Source{output: buffers},
            test_bin: %TestSinkBin{
              filter: TestFilter,
              sink: Testing.Sink
            }
          ]
        })

      Testing.Pipeline.play(pipeline) == :ok

      assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
      assert_pipeline_playback_changed(pipeline, :prepared, :playing)

      assert_start_of_stream(pipeline, :test_bin)

      buffers
      |> Enum.each(fn b ->
        assert_sink_buffer(pipeline, :test_bin, %Membrane.Buffer{payload: ^b})
      end)

      assert_end_of_stream(pipeline, :test_bin)
    end
  end

  describe "Events passing in pipeline" do
    test "notifications are handled by bin as if it's a pipeline" do
      {:ok, pipeline} =
        Testing.Pipeline.start_link(%Testing.Pipeline.Options{
          elements: [
            source: Testing.Source,
            test_bin: %TestBin{
              filter1: TestFilter,
              filter2: TestFilter
            },
            sink: %Testing.Sink{autodemand: false}
          ]
        })

      Testing.Pipeline.play(pipeline) == :ok

      assert_pipeline_playback_changed(pipeline, :stopped, :prepared)
      assert_pipeline_playback_changed(pipeline, :prepared, :playing)

      {:ok, filter1_pid} = get_child_pid(pipeline, [:test_bin, :filter1])

      send(filter1_pid, {:notify_parent, :some_example_notification})

      # As this test's implementation of bin only passes notifications up
      assert_pipeline_notified(pipeline, :test_bin, :some_example_notification)
    end
  end

  # TODO move to some test utils?
  defp get_child_pid(last_child_pid, []) when is_pid(last_child_pid) do
    {:ok, last_child_pid}
  end

  defp get_child_pid(last_child_pid, [child | children]) when is_pid(last_child_pid) do
    state = :sys.get_state(last_child_pid)
    child_pid = state.children[child]
    get_child_pid(child_pid, children)
  end

  defp get_child_pid(_, _) do
    {:error, :child_was_not_found}
  end
end
