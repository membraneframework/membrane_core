defmodule Membrane.Support.Bin.TestBins do
  alias Membrane.ParentSpec

  defmodule TestFilter do
    use Membrane.Filter

    def_output_pad :output, caps: :any

    def_input_pad :input, demand_unit: :buffers, caps: :any

    @impl true
    def handle_other({:notify_parent, notif}, _ctx, state), do: {{:ok, notify: notif}, state}

    @impl true
    def handle_demand(:output, size, _, _ctx, state), do: {{:ok, demand: {:input, size}}, state}

    @impl true
    def handle_process(_pad, buf, _, state), do: {{:ok, buffer: {:output, buf}}, state}
  end

  defmodule SimpleBin do
    use Membrane.Bin

    def_options filter1: [type: :atom],
                filter2: [type: :atom]

    def_input_pad :input, demand_unit: :buffers, caps: :any

    def_output_pad :output, caps: :any, demand_unit: :buffers

    @impl true
    def handle_init(opts) do
      children = [
        filter1: opts.filter1,
        filter2: opts.filter2
      ]

      links = %{
        {Bin.itself(), :input} => {:filter1, :input, []},
        {:filter1, :output} => {:filter2, :input, []},
        {:filter2, :output} => {Bin.itself(), :output, []}
      }

      spec = %ParentSpec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end
  end

  defmodule TestDynamicPadBin do
    use Membrane.Bin

    def_options filter1: [type: :atom],
                filter2: [type: :atom]

    def_input_pad :input, demand_unit: :buffers, caps: :any, availability: :on_request

    def_output_pad :output, caps: :any, availability: :on_request, demand_unit: :buffers

    @impl true
    def handle_init(opts) do
      children = [
        filter1: opts.filter1,
        filter2: opts.filter2
      ]

      links = %{
        {Bin.itself(), :input} => {:filter1, :input, []},
        {:filter1, :output} => {:filter2, :input, []},
        {:filter2, :output} => {Bin.itself(), :output, []}
      }

      spec = %ParentSpec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end

    def handle_pad_added(_pad_ref, _ctx, state), do: {:ok, state}
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
        {Bin.itself(), :input} => {:filter, :input, []},
        {:filter, :output} => {:sink, :input, []}
      }

      spec = %ParentSpec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_element_start_of_stream(arg, state) do
      {{:ok, notify: {:handle_element_start_of_stream, arg}}, state}
    end

    @impl true
    def handle_element_end_of_stream(arg, state) do
      {{:ok, notify: {:handle_element_end_of_stream, arg}}, state}
    end
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
        {:source, :output} => {:sink, :input, []}
      }

      spec = %ParentSpec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_element_start_of_stream(arg, state) do
      {{:ok, notify: {:handle_element_start_of_stream, arg}}, state}
    end

    @impl true
    def handle_element_end_of_stream(arg, state) do
      {{:ok, notify: {:handle_element_end_of_stream, arg}}, state}
    end
  end
end
