defmodule Membrane.Support.Bin.TestBins do
  @moduledoc false
  alias Membrane.ChildrenSpec

  defmodule TestFilter do
    @moduledoc false
    use Membrane.Filter

    def_output_pad :output, accepted_format: _any

    def_input_pad :input, demand_unit: :buffers, accepted_format: _any

    @impl true
    def handle_info({:notify_parent, notif}, _ctx, state),
      do: {[notify_parent: notif], state}

    @impl true
    def handle_demand(:output, size, _unit, _ctx, state),
      do: {[demand: {:input, size}], state}

    @impl true
    def handle_process(_pad, buf, _ctx, state), do: {[buffer: {:output, buf}], state}
  end

  defmodule TestDynamicPadFilter do
    @moduledoc false
    use Membrane.Filter

    def_output_pad :output, accepted_format: _any, availability: :on_request

    def_input_pad :input, demand_unit: :buffers, accepted_format: _any, availability: :on_request

    @impl true
    def handle_info({:notify_parent, notif}, _ctx, state),
      do: {[notify_parent: notif], state}

    @impl true
    def handle_demand(_output, _size, _unit, ctx, state) do
      min_demand =
        ctx.pads
        |> Map.values()
        |> Enum.filter(&(&1.direction == :output))
        |> Enum.map(& &1.demand)
        |> Enum.min()

      demands =
        ctx.pads
        |> Map.values()
        |> Enum.filter(&(&1.direction == :input))
        |> Enum.map(&{:demand, {&1.ref, min_demand}})

      {demands, state}
    end

    @impl true
    def handle_process(_input, buf, ctx, state) do
      buffers =
        ctx.pads
        |> Map.values()
        |> Enum.filter(&(&1.direction == :output))
        |> Enum.map(&{:buffer, {&1.ref, buf}})

      {buffers, state}
    end
  end

  defmodule SimpleBin do
    @moduledoc false
    use Membrane.Bin

    def_options filter1: [type: :atom],
                filter2: [type: :atom]

    def_input_pad :input, accepted_format: _any, demand_unit: :buffers

    def_output_pad :output, accepted_format: _any, demand_unit: :buffers

    @impl true
    def handle_init(_ctx, opts) do
      links = [
        bin_input()
        |> child(:filter1, opts.filter1)
        |> child(:filter2, opts.filter2)
        |> bin_output()
      ]

      state = %{}

      {[spec: links], state}
    end

    @impl true
    def handle_info(msg, _ctx, state) do
      {[notify_parent: msg], state}
    end
  end

  defmodule CrashTestBin do
    @moduledoc false
    use Membrane.Bin

    def_input_pad :input, demand_unit: :buffers, accepted_format: _any, availability: :on_request

    def_output_pad :output,
      accepted_format: _any,
      availability: :on_request,
      demand_unit: :buffers

    @impl true
    def handle_init(_ctx, _opts) do
      children = [
        child(:filter, Membrane.Support.ChildCrashTest.Filter)
      ]

      state = %{}

      {[spec: children], state}
    end

    @impl true
    def handle_pad_added(Pad.ref(:input, _id) = pad, _ctx, state) do
      links = [
        bin_input(pad) |> get_child(:filter)
      ]

      {[notify_parent: {:handle_pad_added, pad}, spec: links], state}
    end

    def handle_pad_added(Pad.ref(:output, _id) = pad, _ctx, state) do
      links = [
        get_child(:filter) |> bin_output(pad)
      ]

      {[notify_parent: {:handle_pad_added, pad}, spec: links], state}
    end
  end

  defmodule TestDynamicPadBin do
    @moduledoc false
    use Membrane.Bin

    def_options filter1: [type: :atom],
                filter2: [type: :atom]

    def_input_pad :input, demand_unit: :buffers, accepted_format: _any, availability: :on_request

    def_output_pad :output,
      accepted_format: _any,
      availability: :on_request,
      demand_unit: :buffers

    @impl true
    def handle_init(_ctx, opts) do
      links = [
        child(:filter1, opts.filter1) |> child(:filter2, opts.filter2)
      ]

      state = %{}

      {[spec: links], state}
    end

    @impl true
    def handle_pad_added(Pad.ref(:input, _id) = pad, _ctx, state) do
      links = [
        bin_input(pad) |> get_child(:filter1)
      ]

      {[notify_parent: {:handle_pad_added, pad}, spec: links], state}
    end

    def handle_pad_added(Pad.ref(:output, _id) = pad, _ctx, state) do
      links = [
        get_child(:filter2) |> bin_output(pad)
      ]

      {[notify_parent: {:handle_pad_added, pad}, spec: links], state}
    end
  end

  defmodule TestSinkBin do
    @moduledoc false
    use Membrane.Bin

    def_options filter: [type: :atom],
                sink: [type: :atom]

    def_input_pad :input, demand_unit: :buffers, accepted_format: _any

    @impl true
    def handle_init(_ctx, opts) do
      links = [bin_input() |> child(:filter, opts.filter) |> child(:sink, opts.sink)]

      state = %{}

      {[spec: links], state}
    end

    @impl true
    def handle_child_notification(notification, _element, _ctx, state) do
      {[notify_parent: notification], state}
    end

    @impl true
    def handle_element_start_of_stream(element, pad, _ctx, state) do
      {[notify_parent: {:handle_element_start_of_stream, element, pad}], state}
    end

    @impl true
    def handle_element_end_of_stream(element, pad, _ctx, state) do
      {[notify_parent: {:handle_element_end_of_stream, element, pad}], state}
    end
  end

  defmodule TestPadlessBin do
    @moduledoc false
    use Membrane.Bin

    def_options source: [type: :atom],
                sink: [type: :atom]

    @impl true
    def handle_init(_ctx, opts) do
      links = [child(:source, opts.source) |> child(:sink, opts.sink)]

      state = %{}

      {[spec: links], state}
    end

    @impl true
    def handle_child_notification(notification, _element, _ctx, state) do
      {[notify_parent: notification], state}
    end

    @impl true
    def handle_element_start_of_stream(element, pad, _ctx, state) do
      {[notify_parent: {:handle_element_start_of_stream, element, pad}], state}
    end

    @impl true
    def handle_element_end_of_stream(element, pad, _ctx, state) do
      {[notify_parent: {:handle_element_end_of_stream, element, pad}], state}
    end
  end

  defmodule NotifyingParentElement do
    @moduledoc false
    use Membrane.Filter

    def_input_pad :input, demand_unit: :buffers, accepted_format: _any
    def_output_pad :output, accepted_format: _any, demand_unit: :buffers

    @impl true
    def handle_init(_ctx, _opts) do
      {[], %{}}
    end

    @impl true
    def handle_parent_notification(notification, _ctx, state) do
      {[notify_parent: {"filter1", notification}], state}
    end

    @impl true
    def handle_demand(_pad, _size, _unit, _ctx, state) do
      {[], state}
    end
  end

  defmodule NotifyingParentBin do
    @moduledoc false
    use Membrane.Bin

    def_input_pad :input, demand_unit: :buffers, accepted_format: _any

    def_output_pad :output, accepted_format: _any, demand_unit: :buffers

    @impl true
    def handle_init(_ctx, _opts) do
      links = [
        bin_input()
        |> child(:filter1, NotifyingParentElement)
        |> child(:filter2, NotifyingParentElement)
        |> bin_output()
      ]

      state = %{}

      {[spec: links], state}
    end

    @impl true
    def handle_parent_notification(notification, _ctx, state) do
      {[notify_child: {:filter1, notification}], state}
    end

    @impl true
    def handle_child_notification(notification, :filter1, _ctx, state) do
      {[notify_parent: notification], state}
    end
  end
end
