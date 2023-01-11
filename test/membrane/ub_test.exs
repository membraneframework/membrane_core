defmodule Membrane.UBTest do
  use ExUnit.Case

  require Membrane.Pad

  alias Membrane.Pad
  alias Membrane.Testing.Pipeline

  import Membrane.ChildrenSpec

  defmodule Element do
    use Membrane.Endpoint

    def_input_pad :input, accepted_format: _any, mode: :push, availability: :on_request
    def_output_pad :output, accepted_format: _any, mode: :push, availability: :on_request

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      IO.inspect(self(), label: "ELEMENT handle_pad_added #{inspect(pad)}")
      {[], state}
    end

    @impl true
    def handle_pad_removed(pad, _ctx, state) do
      IO.inspect(self(), label: "ELEMENT handle_pad_removed #{inspect(pad)}")
      {[], state}
    end

    @impl true
    def handle_terminate_request(_ctx, state) do
      IO.inspect(self(), label: "ELEMENT terminating")
      {[terminate: :normal], state}
    end
  end

  defmodule Bin do
    use Membrane.Bin

    def_input_pad :input, accepted_format: _any, mode: :push, availability: :on_request
    def_output_pad :output, accepted_format: _any, mode: :push, availability: :on_request

    @impl true
    def handle_pad_added(pad, _ctx, state) do
      IO.inspect(self(), label: "BIN handle_pad_added #{inspect(pad)}")

      spec =
        child(pad, Membrane.UBTest.Element)
        |> via_out(pad)
        |> bin_output(pad)

      {[spec: spec], state}
    end

    @impl true
    def handle_pad_removed(pad, _ctx, state) do
      IO.inspect(self(), label: "BIN handle_pad_removed #{inspect(pad)}")
      {[remove_children: pad], state}
      # {[], state}
    end

    @impl true
    def handle_parent_notification({:remove_link, child} = msg, _ctx, state) do
      IO.inspect(self(), label: "BIN handle_parent_notification #{inspect(msg)}")
      {[remove_children: child], state}
      # {[remove_link: {child, child}], state}
    end

    @impl true
    def handle_terminate_request(_ctx, state) do
      IO.inspect(self(), label: "BIN terminating")
      {[terminate: :normal], state}
    end
  end

  @tag :target
  test "undefined behaviour" do
    pad_ref = Pad.ref(:output, 1)

    pipeline =
      Pipeline.start_link_supervised!(
        spec:
          child(:bin, Bin)
          |> via_out(pad_ref)
          |> child(:element, Element)
      )

    Process.sleep(1000)

    Pipeline.execute_actions(pipeline, notify_child: {:bin, {:remove_link, pad_ref}})

    Process.sleep(1000)
  end
end
