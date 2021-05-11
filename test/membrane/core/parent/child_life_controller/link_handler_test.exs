defmodule Membrane.Core.Parent.ChildLifeController.LinkHandlerTest do
  use ExUnit.Case

  import Membrane.ParentSpec

  alias Membrane.ChildEntry

  alias Membrane.Core.Message
  alias Membrane.Core.Parent.LinkParser
  alias Membrane.Core.Parent.ChildLifeController.LinkHandler
  alias Membrane.LinkError
  alias Membrane.Pad
  alias Membrane.Support.Bin.TestBins.{TestDynamicPadFilter, TestFilter}

  require Membrane.Core.Message
  require Membrane.Pad

  defp get_state(child_module, opts \\ []) do
    pid = Keyword.get(opts, :pid, nil)
    availability = Keyword.get(opts, :availability, :always)

    %Membrane.Core.Bin.State{
      module: nil,
      name: :my_bin,
      synchronization: %{},
      children: [
        a: %ChildEntry{module: child_module, pid: pid},
        b: %ChildEntry{module: child_module, pid: pid},
        c: %ChildEntry{module: child_module, pid: pid}
      ],
      pads: %{
        info:
          [input: %{availability: availability}, output: %{availability: availability}]
          |> Enum.flat_map(fn {name, info} -> [{name, info}, {{:private, name}, info}] end)
          |> Map.new(),
        data: %{}
      }
    }
  end

  defp endpoints(links) do
    links |> Enum.flat_map(&[&1.from, &1.to])
  end

  describe "resolve links" do
    test "should work for static pads" do
      {links, []} = LinkParser.parse([link(:a) |> to(:b)])
      resolved_links = LinkHandler.resolve_links(links, get_state(TestFilter))
      endpoints(resolved_links) |> Enum.each(&assert &1.pad_ref == &1.pad_spec)
    end

    test "should work for dynamic pads" do
      {links, []} = LinkParser.parse([link(:a) |> to(:b)])

      resolved_links = LinkHandler.resolve_links(links, get_state(TestDynamicPadFilter))

      endpoints(resolved_links)
      |> Enum.each(fn %{pad_spec: pad, pad_ref: pad_ref} ->
        assert Pad.ref(^pad, _) = pad_ref
      end)

      {links, []} =
        LinkParser.parse([
          link(:a) |> via_out(Pad.ref(:output, :x)) |> via_in(Pad.ref(:input, :y)) |> to(:b)
        ])

      resolved_links = LinkHandler.resolve_links(links, get_state(TestDynamicPadFilter))

      assert [%{pad_ref: Pad.ref(:output, :x)}, %{pad_ref: Pad.ref(:input, :y)}] =
               resolved_links |> endpoints() |> Enum.sort()
    end

    test "should work for bin static pads" do
      {links, []} = LinkParser.parse([link_bin_input() |> to(:a) |> to_bin_output()])

      resolved_links = LinkHandler.resolve_links(links, get_state(TestFilter))
      endpoints(resolved_links) |> Enum.each(&assert &1.pad_ref == &1.pad_spec)

      endpoints(resolved_links)
      |> Enum.filter(&(&1.child == {Membrane.Bin, :itself}))
      |> Enum.each(&assert {:private, _} = &1.pad_ref)
    end

    test "should work for bin dynamic pads" do
      {links, []} =
        LinkParser.parse([
          link_bin_input(Pad.ref(:input, :x)) |> to(:a) |> to_bin_output(Pad.ref(:output, :y))
        ])

      state =
        get_state(TestFilter, availability: :on_request)
        |> put_in([:pads, :data], %{
          Pad.ref(:input, :x) => %Pad.Data{},
          Pad.ref(:output, :y) => %Pad.Data{}
        })

      resolved_links = LinkHandler.resolve_links(links, state)
      endpoints(resolved_links) |> Enum.each(&assert &1.pad_ref == &1.pad_spec)

      endpoints(resolved_links)
      |> Enum.filter(&(&1.child == {Membrane.Bin, :itself}))
      |> Enum.each(&assert Pad.ref({:private, _}, _) = &1.pad_ref)
    end

    test "should fail when trying to link non-existent child" do
      {links, []} = LinkParser.parse([link(:a) |> to(:m)])

      assert_raise LinkError, ~r/child :m does not exist/i, fn ->
        LinkHandler.resolve_links(links, get_state(TestFilter))
      end
    end

    test "should fail when trying to link non-existent pad" do
      {links, []} = LinkParser.parse([link(:a) |> via_out(:x) |> to(:b)])

      assert_raise LinkError, ~r/child :a does not have pad :x/i, fn ->
        LinkHandler.resolve_links(links, get_state(TestFilter))
      end
    end

    test "should fail when trying to pass dynamic pad ref to a static pad" do
      {links, []} = LinkParser.parse([link(:a) |> via_out(Pad.ref(:output, :x)) |> to(:b)])

      assert_raise LinkError,
                   ~r/dynamic pad ref .*membrane.pad.*:output.* passed for static pad of child :a/i,
                   fn ->
                     LinkHandler.resolve_links(links, get_state(TestFilter))
                   end
    end

    test "should fail when trying to link non-existent bin pad" do
      {links, []} = LinkParser.parse([link_bin_input(:x) |> to(:b)])

      assert_raise LinkError, ~r/bin :my_bin does not have pad :x/i, fn ->
        LinkHandler.resolve_links(links, get_state(TestFilter))
      end
    end

    test "should fail when trying to link dynamic bin pad and passed only name" do
      {links, []} = LinkParser.parse([link_bin_input(:input) |> to(:b)])

      assert_raise LinkError,
                   ~r/exact reference not passed when linking dynamic bin pad :input/i,
                   fn ->
                     LinkHandler.resolve_links(
                       links,
                       get_state(TestFilter, availability: :on_request)
                     )
                   end
    end

    test "should fail when trying to link dynamic bin pad that is not externally linked yet" do
      {links, []} = LinkParser.parse([link_bin_input(Pad.ref(:input, :x)) |> to(:b)])

      assert_raise LinkError,
                   ~r/linking dynamic bin pad .*membrane.pad.*:input.* not .* externally linked/i,
                   fn ->
                     LinkHandler.resolve_links(
                       links,
                       get_state(TestFilter, availability: :on_request)
                     )
                   end
    end

    test "should fail when trying to pass dynamic pad ref to a static bin pad" do
      {links, []} = LinkParser.parse([link(:a) |> to_bin_output(Pad.ref(:output, :x))])

      assert_raise LinkError,
                   ~r/dynamic pad ref .*membrane.pad.*:output.* passed for static pad of bin :my_bin/i,
                   fn ->
                     LinkHandler.resolve_links(links, get_state(TestFilter))
                   end
    end
  end

  test "should link resolved pads" do
    defmodule Proxy do
      use GenServer

      @impl true
      def init(pid) do
        {:ok, %{pid: pid}}
      end

      @impl true
      def handle_call(msg, _from, state) do
        send(state.pid, msg)

        reply =
          case msg do
            Message.new(:handle_link, _args) -> {:ok, nil}
            Message.new(:linking_finished) -> :ok
          end

        {:reply, reply, state}
      end
    end

    {:ok, pid} = GenServer.start_link(Proxy, self())
    state = get_state(TestFilter, pid: pid)
    {links, []} = LinkParser.parse([link(:a) |> to(:b)])
    resolved_links = LinkHandler.resolve_links(links, state)
    assert {:ok, _state} = LinkHandler.link_children(resolved_links, state)
    assert_receive Message.new(:handle_link, _args)
    assert_receive Message.new(:linking_finished)
    assert_receive Message.new(:linking_finished)
    refute_receive Message.new(_name, _args, _opts)
  end
end
