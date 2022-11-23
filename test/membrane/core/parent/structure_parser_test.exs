defmodule Membrane.Core.Parent.StructureParserTest do
  use ExUnit.Case

  import Membrane.ChildrenSpec
  require Membrane.ChildrenSpec

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
      |> bin_output()
    ]

    assert {[], links} = StructureParser.parse(links_spec)

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

    links_spec = [
      get_child(:a) |> get_child(:b) |> get_child(:c),
      get_child(:d) |> get_child(:b) |> get_child(:e)
    ]

    assert {[], links} = StructureParser.parse(links_spec)

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

    [
      [get_child(:b) |> via_out(:x)],
      [get_child(:c) |> via_in(:y)],
      [bin_input()]
    ]
    |> Enum.each(fn link_spec ->
      assert_raise Membrane.ParentError,
                   ~r/.*Invalid structure specification.*/,
                   fn -> StructureParser.parse(link_spec) end
    end)
  end

  test "link creating children" do
    import Membrane.ChildrenSpec

    links_spec = [child(:a, A) |> child(:b, B) |> child(:c, C)]

    links_spec =
      Membrane.Core.Parent.ChildLifeController.make_canonical(links_spec) |> Enum.at(0) |> elem(0)

    assert {children, links} = StructureParser.parse(links_spec)

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
             {:a, A, %{get_if_exists: false}},
             {:b, B, %{get_if_exists: false}},
             {:c, C, %{get_if_exists: false}}
           ]
  end

  test "if the conditional linking works properly" do
    links_spec =
      child(:a, A)
      |> ignore_unless true do
        child(:b, B) |> child(:c, C)
      end
      |> child(:d, D)

    links_spec =
      Membrane.Core.Parent.ChildLifeController.make_canonical(links_spec) |> Enum.at(0) |> elem(0)

    assert {children, links} = StructureParser.parse(links_spec)

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
                 child: :c,
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
             {:a, A, %{get_if_exists: false}},
             {:b, B, %{get_if_exists: false}},
             {:c, C, %{get_if_exists: false}},
             {:d, D, %{get_if_exists: false}}
           ]
  end

  test "if the conditional linking works properly 2" do
    links_spec =
      child(:a, A)
      |> ignore_unless false do
        child(:b, B)
      end
      |> child(:c, C)

    links_spec =
      Membrane.Core.Parent.ChildLifeController.make_canonical(links_spec) |> Enum.at(0) |> elem(0)

    assert {children, links} = StructureParser.parse(links_spec)

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
             }
           ] = links

    assert Enum.sort(children) == [
             {:a, A, %{get_if_exists: false}},
             {:c, C, %{get_if_exists: false}}
           ]
  end

  test "if nested conditional linking works properly" do
    links_spec = [
      child(:a, A)
      |> ignore_unless true do
        child(:b, B)
        |> ignore_unless false do
          child(:c, C)
        end
      end
      |> child(:d, D)
    ]

    links_spec =
      Membrane.Core.Parent.ChildLifeController.make_canonical(links_spec) |> Enum.at(0) |> elem(0)

    assert {children, links} = StructureParser.parse(links_spec)

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
             {:a, A, %{get_if_exists: false}},
             {:b, B, %{get_if_exists: false}},
             {:d, D, %{get_if_exists: false}}
           ]
  end

  test "if nested conditional linking works properly 2" do
    links_spec = [
      child(:a, A)
      |> ignore_unless false do
        child(:b, B)
        |> ignore_unless true do
          child(:c, C)
        end
      end
      |> child(:d, D)
    ]

    assert {children, links} = StructureParser.parse(links_spec)

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
             }
           ] = links

    assert Enum.sort(children) == [
             {:a, A, %{get_if_exists: false}},
             {:d, D, %{get_if_exists: false}}
           ]
  end
end
