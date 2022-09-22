defmodule Membrane.Core.Parent.StructureParserTest do
  use ExUnit.Case

  alias Membrane.Core.Parent.{Link, StructureParser}
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
    import Membrane.ParentSpec

    links_spec = [link(:a) |> to(:b) |> to(:c), link(:d) |> to(:b) |> to(:e)]

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
                   fn -> StructureParser.parse(link_spec) end
    end)
  end

  test "link creating children" do
    import Membrane.ParentSpec

    links_spec = [spawn_child(:a, A) |> to_new(:b, B) |> to_new(:c, C)]
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
             b: {B, :dont_spawn_if_already_exists},
             c: {C, :dont_spawn_if_already_exists}
           ]
  end

  test "Membrane.ParentSpec.link_linear/1 links children in a linear manner" do
    import Membrane.ParentSpec
    children = [source: nil, filter: nil, sink: nil]
    desired_links = [spawn_child(:source, nil) |> to_new(:filter, nil) |> to_new(:sink, nil)]
    auto_generated_links = link_linear(children)
    assert desired_links == auto_generated_links
  end


  test "if the conditional linking works properly" do
    import Membrane.ParentSpec

    links_spec = [spawn_child(:a, A) |> ignore_unless(true) |> to_new(:b, B) |> end_ignore() |> to_new(:c, C)]
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
          b: {B, :dont_spawn_if_already_exists},
          c: {C, :dont_spawn_if_already_exists}
        ]
  end


  test "if the conditional linking works properly 2" do
    import Membrane.ParentSpec

    links_spec = [spawn_child(:a, A) |> ignore_unless(false) |> to_new(:b, B) |> end_ignore() |> to_new(:c, C)]
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
          child: :c,
          pad_props: %{},
          pad_spec: :input,
          pad_ref: nil,
          pid: nil
        }
      },
    ] = links

    assert Enum.sort(children) == [
          a: A,
          c: {C, :dont_spawn_if_already_exists}
        ]
  end

  test "if nested conditional linking works properly" do
    import Membrane.ParentSpec

    links_spec = [spawn_child(:a, A) |> ignore_unless(true) |> to_new(:b, B) |> ignore_unless(false) |> to_new(:c, C) |> end_ignore() |> end_ignore() |> to_new(:d, D)]
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
          child: :d,
          pad_props: %{},
          pad_spec: :input,
          pad_ref: nil,
          pid: nil
        }
      }
    ] = links

    assert Enum.sort(children) == [
          a: A,
          b: {B, :dont_spawn_if_already_exists},
          d: {D, :dont_spawn_if_already_exists}
        ]
  end


  test "if nested conditional linking works properly 2" do
    import Membrane.ParentSpec

    links_spec = [spawn_child(:a, A) |> ignore_unless(false) |> to_new(:b, B) |> ignore_unless(true) |> to_new(:c, C) |> end_ignore() |> end_ignore() |> to_new(:d, D)]
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
          child: :d,
          pad_props: %{},
          pad_spec: :input,
          pad_ref: nil,
          pid: nil
        }
      },
    ] = links

    assert Enum.sort(children) == [
          a: A,
          d: {D, :dont_spawn_if_already_exists}
        ]
  end



  test "if to_new/3 don't create new children if a children with given name already exists" do

  end

  test "if to_new/3 create a new children if a children with given name doesn't exist" do

  end
end
