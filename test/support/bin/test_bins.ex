defmodule Membrane.Support.Bin.TestBins do
  @moduledoc false
  alias Membrane.ParentSpec

  defmodule TestFilter do
    @moduledoc false
    use Membrane.Filter

    def_output_pad :output, caps: :any

    def_input_pad :input, demand_unit: :buffers, caps: :any

    @impl true
    def handle_other({:notify_parent, notif}, _ctx, state),
      do: {{:ok, notify_parent: notif}, state}

    @impl true
    def handle_demand(:output, size, _unit, _ctx, state),
      do: {{:ok, demand: {:input, size}}, state}

    @impl true
    def handle_process(_pad, buf, _ctx, state), do: {{:ok, buffer: {:output, buf}}, state}
  end

  defmodule TestDynamicPadFilter do
    @moduledoc false
    use Membrane.Filter

    def_output_pad :output, caps: :any, availability: :on_request

    def_input_pad :input, demand_unit: :buffers, caps: :any, availability: :on_request

    @impl true
    def handle_other({:notify_parent, notif}, _ctx, state),
      do: {{:ok, notify_parent: notif}, state}

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

      {{:ok, demands}, state}
    end

    @impl true
    def handle_process(_input, buf, ctx, state) do
      buffers =
        ctx.pads
        |> Map.values()
        |> Enum.filter(&(&1.direction == :output))
        |> Enum.map(&{:buffer, {&1.ref, buf}})

      {{:ok, buffers}, state}
    end
  end

  defmodule SimpleBin do
    @moduledoc false
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

      links = [
        link_bin_input() |> to(:filter1) |> to(:filter2) |> to_bin_output()
      ]

      spec = %ParentSpec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_other(msg, _ctx, state) do
      {{:ok, notify_parent: msg}, state}
    end
  end

  defmodule CrashTestBin do
    @moduledoc false
    use Membrane.Bin

    def_input_pad :input, demand_unit: :buffers, caps: :any, availability: :on_request

    def_output_pad :output, caps: :any, availability: :on_request, demand_unit: :buffers

    @impl true
    def handle_init(_opts) do
      children = [
        filter: Membrane.Support.ChildCrashTest.Filter
      ]

      spec = %ParentSpec{
        children: children
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_pad_added(Pad.ref(:input, _id) = pad, _ctx, state) do
      links = [
        link_bin_input(pad) |> to(:filter)
      ]

      {{:ok, notify_parent: {:handle_pad_added, pad}, spec: %ParentSpec{links: links}}, state}
    end

    def handle_pad_added(Pad.ref(:output, _id) = pad, _ctx, state) do
      links = [
        link(:filter) |> to_bin_output(pad)
      ]

      {{:ok, notify_parent: {:handle_pad_added, pad}, spec: %ParentSpec{links: links}}, state}
    end
  end

  defmodule TestDynamicPadBin do
    @moduledoc false
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

      links = [
        link(:filter1) |> to(:filter2)
      ]

      spec = %ParentSpec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_pad_added(Pad.ref(:input, _id) = pad, _ctx, state) do
      links = [
        link_bin_input(pad) |> to(:filter1)
      ]

      {{:ok, notify_parent: {:handle_pad_added, pad}, spec: %ParentSpec{links: links}}, state}
    end

    def handle_pad_added(Pad.ref(:output, _id) = pad, _ctx, state) do
      links = [
        link(:filter2) |> to_bin_output(pad)
      ]

      {{:ok, notify_parent: {:handle_pad_added, pad}, spec: %ParentSpec{links: links}}, state}
    end
  end

  defmodule TestSinkBin do
    @moduledoc false
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

      links = [link_bin_input() |> to(:filter) |> to(:sink)]

      spec = %ParentSpec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_child_notification(notification, _element, _ctx, state) do
      {{:ok, notify_parent: notification}, state}
    end

    @impl true
    def handle_element_start_of_stream(element, pad, _ctx, state) do
      {{:ok, notify_parent: {:handle_element_start_of_stream, element, pad}}, state}
    end

    @impl true
    def handle_element_end_of_stream(element, pad, _ctx, state) do
      {{:ok, notify_parent: {:handle_element_end_of_stream, element, pad}}, state}
    end
  end

  defmodule TestPadlessBin do
    @moduledoc false
    use Membrane.Bin

    def_options source: [type: :atom],
                sink: [type: :atom]

    @impl true
    def handle_init(opts) do
      children = [
        source: opts.source,
        sink: opts.sink
      ]

      links = [link(:source) |> to(:sink)]

      spec = %ParentSpec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_child_notification(notification, _element, _ctx, state) do
      {{:ok, notify_parent: notification}, state}
    end

    @impl true
    def handle_element_start_of_stream(element, pad, _ctx, state) do
      {{:ok, notify_parent: {:handle_element_start_of_stream, element, pad}}, state}
    end

    @impl true
    def handle_element_end_of_stream(element, pad, _ctx, state) do
      {{:ok, notify_parent: {:handle_element_end_of_stream, element, pad}}, state}
    end
  end

  defmodule NotifyingParentElement do
    @moduledoc false
    use Membrane.Filter

    def_input_pad :input, demand_unit: :buffers, caps: :any
    def_output_pad :output, caps: :any, demand_unit: :buffers

    @impl true
    def handle_init(_opts) do
      {:ok, %{}}
    end

    @impl true
    def handle_parent_notification(notification, _ctx, state) do
      {{:ok, notify_parent: {"filter1", notification}}, state}
    end

    @impl true
    def handle_demand(_pad, _size, _unit, _ctx, state) do
      {{:ok, []}, state}
    end
  end

  defmodule NotifyingParentBin do
    @moduledoc false
    use Membrane.Bin

    def_input_pad :input, demand_unit: :buffers, caps: :any

    def_output_pad :output, caps: :any, demand_unit: :buffers

    @impl true
    def handle_init(_opts) do
      children = [
        filter1: NotifyingParentElement,
        filter2: NotifyingParentElement
      ]

      links = [
        link_bin_input() |> to(:filter1) |> to(:filter2) |> to_bin_output()
      ]

      spec = %ParentSpec{
        children: children,
        links: links
      }

      state = %{}

      {{:ok, spec: spec}, state}
    end

    @impl true
    def handle_parent_notification(notification, _ctx, state) do
      {{:ok, notify_child: {:filter1, notification}}, state}
    end

    @impl true
    def handle_child_notification(notification, :filter1, _ctx, state) do
      {{:ok, notify_parent: notification}, state}
    end
  end
end
