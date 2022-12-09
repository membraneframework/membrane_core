defmodule Membrane.Core.Parent.SpecificationParserTest do
  use ExUnit.Case

  alias Membrane.Core.Parent.{Link, SpecificationParser}
  alias Membrane.Core.Parent.Link.Endpoint

  defmodule A do
    use Membrane.Filter
  end

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

    assert {[], links} = SpecificationParser.parse(links_spec)

    assert [
             %Link{
               from: %Endpoint{
                 child: {:child_ref, :a},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_ref, :b},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:child_ref, :b},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_ref, :c},
                 pad_props: %{options: [q: 1]},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:child_ref, :c},
                 pad_props: %{},
                 pad_spec: :x,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_ref, :d},
                 pad_props: %{},
                 pad_spec: Pad.ref(:y, 2),
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:child_ref, :d},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_ref, {Membrane.Bin, :itself}},
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

    assert {[], links} = SpecificationParser.parse(links_spec)

    assert [
             %Link{
               from: %Endpoint{
                 child: {:child_ref, :a},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_ref, :b},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:child_ref, :b},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_ref, :c},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:child_ref, :d},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_ref, :b},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:child_ref, :b},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_ref, :e},
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
      assert_raise Membrane.ParentError, ~r/.*Invalid specification.*:abc/, fn ->
        SpecificationParser.parse(link_spec)
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
                   ~r/.*Invalid specification.*/,
                   fn -> SpecificationParser.parse(link_spec) end
    end)
  end

  test "link creating children" do
    import Membrane.ChildrenSpec

    links_spec = [child(:a, A) |> child(:b, A) |> child(:c, A)]
    assert {children, links} = SpecificationParser.parse(links_spec)

    assert [
             %Link{
               from: %Endpoint{
                 child: {:child_name, :a},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_name, :b},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:child_name, :b},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:child_name, :c},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             }
           ] = links

    assert Enum.sort(children) == [
             {{:child_name, :a}, A, %{get_if_exists: false}},
             {{:child_name, :b}, A, %{get_if_exists: false}},
             {{:child_name, :c}, A, %{get_if_exists: false}}
           ]
  end
end
