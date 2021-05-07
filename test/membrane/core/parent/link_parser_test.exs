defmodule Membrane.Core.Parent.LinkParserTest do
  use ExUnit.Case

  alias Membrane.Core.Parent.{Link, LinkParser}
  alias Membrane.Core.Parent.Link.Endpoint

  test "valid link" do
    import Membrane.ParentSpec
    require Membrane.Pad
    alias Membrane.Pad

    links_spec = [
      link(:a)
      |> to(:b)
      |> via_in(:input, options: [q: 1])
      |> to(:c)
      |> via_out(:x)
      |> via_in(Pad.ref(:y, 2))
      |> to(:d)
      |> to_bin_output()
    ]

    assert {links, []} = LinkParser.parse(links_spec)

    assert links == [
             %Link{
               from: %Endpoint{
                 child: :a,
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :b,
                 pad_props: [],
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :b,
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :c,
                 pad_props: [options: [q: 1]],
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :c,
                 pad_props: [],
                 pad_spec: :x,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :d,
                 pad_props: [],
                 pad_spec: Pad.ref(:y, 2),
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :d,
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {Membrane.Bin, :itself},
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               }
             }
           ]
  end

  test "link with multiple branches" do
    import Membrane.ParentSpec

    links_spec = [link(:a) |> to(:b) |> to(:c), link(:d) |> to(:b) |> to(:e)]

    assert {links, []} = LinkParser.parse(links_spec)

    assert links == [
             %Link{
               from: %Endpoint{
                 child: :a,
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :b,
                 pad_props: [],
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :b,
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :c,
                 pad_props: [],
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :d,
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :b,
                 pad_props: [],
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :b,
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :e,
                 pad_props: [],
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             }
           ]
  end

  test "invalid link" do
    [:abc, [:abc], %{{:abc, :output} => {:def, :input}}]
    |> Enum.each(fn link_spec ->
      assert_raise Membrane.ParentError, ~r/.*Invalid links specification.*:abc/, fn ->
        LinkParser.parse(link_spec)
      end
    end)
  end

  test "incomplete link" do
    import Membrane.ParentSpec

    %{
      :a => [link(:a)],
      :b => [link(:b) |> via_out(:x)],
      :c => [link(:c) |> via_in(:y)],
      {Membrane.Bin, :itself} => [link_bin_input()]
    }
    |> Enum.each(fn {from, link_spec} ->
      assert_raise Membrane.ParentError,
                   ~r/.*link from #{inspect(from)} lacks its destination.*/,
                   fn -> LinkParser.parse(link_spec) end
    end)
  end

  test "link creating children" do
    import Membrane.ParentSpec

    links_spec = [link(:a, A) |> to(:b, B) |> to(:c, C)]
    assert {links, children} = LinkParser.parse(links_spec)

    assert links == [
             %Link{
               from: %Endpoint{
                 child: :a,
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :b,
                 pad_props: [],
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: :b,
                 pad_props: [],
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: :c,
                 pad_props: [],
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             }
           ]

    assert Enum.sort(children) == [a: A, b: B, c: C]
  end
end
