defmodule Membrane.Core.Parent.StructureParserTest do
  use ExUnit.Case

  alias Membrane.Core.Parent.{Link, StructureParser}
  alias Membrane.Core.Parent.Link.Endpoint

  test "valid link" do
    import Membrane.ChildrenSpec
    require Membrane.Pad
    alias Membrane.Pad

    links_spec = [
      get_child(:a)
      |> get_child(:b)
      |> via_in(:input, options: [q: 1])
      |> get_child(:c)
      |> via_out(:x)
      |> via_in(Pad.ref(:y, 2))
      |> get_child(:d)
      |> to_bin_output()
    ]

    assert {links, []} = StructureParser.parse(links_spec)

    assert [
             %Link{
               from: %Endpoint{
                 child: :a,
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :b,
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :b,
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :c,
                 pad_props: %{options: [q: 1]},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :c,
                 pad_props: %{},
                 pad_spec: :x,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :d,
                 pad_props: %{},
                 pad_spec: Pad.ref(:y, 2),
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :d,
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {Membrane.Bin, :itself},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               }
             }
           ] = links
  end

  test "link with multiple branches" do
    import Membrane.ChildrenSpec

    links_spec = [get_child(:a) |> get_child(:b) |> get_child(:c), get_child(:d) |> get_child(:b) |> get_child(:e)]

    assert {links, []} = StructureParser.parse(links_spec)

    assert [
             %Link{
               from: %Endpoint{
                 child: :a,
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :b,
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :b,
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :c,
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :d,
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :b,
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :b,
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :e,
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             }
           ] = links
  end

  test "invalid link" do
    [:abc, [:abc], %{{:abc, :output} => {:def, :input}}]
    |> Enum.each(fn link_spec ->
      assert_raise Membrane.ParentError, ~r/.*Invalid structure specification.*:abc/, fn ->
        StructureParser.parse(link_spec)
      end
    end)
  end

  test "incomplete link" do
    import Membrane.ChildrenSpec

    %{
      :a => [get_child(:a)],
      :b => [get_child(:b) |> via_out(:x)],
      :c => [get_child(:c) |> via_in(:y)],
      {Membrane.Bin, :itself} => [link_bin_input()]
    }
    |> Enum.each(fn {from, link_spec} ->
      assert_raise Membrane.ParentError,
                   ~r/.*link from #{inspect(from)} lacks its destination.*/,
                   fn -> StructureParser.parse(link_spec) end
    end)
  end

  test "link creating children" do
    import Membrane.ChildrenSpec

    links_spec = [child(:a, A) |> child(:b, B) |> child(:c, C)]
    assert {links, children} = StructureParser.parse(links_spec)

    assert [
             %Link{
               from: %Endpoint{
                 child: :a,
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :b,
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :b,
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :c,
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             }
           ] = links

    assert Enum.sort(children) == [
             a: A,
             b: B,
             c: C
           ]
  end

  test "Membrane.ChildrenSpec.link_linear/1 links children in a linear manner" do
    import Membrane.ChildrenSpec
    children = [source: nil, filter: nil, sink: nil]
    desired_links = [child(:source, nil) |> child(:filter, nil) |> child(:sink, nil)]
    auto_generated_links = link_linear(children)
    assert desired_links == auto_generated_links
  end
end
