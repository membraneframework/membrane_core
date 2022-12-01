defmodule Membrane.Core.Parent.StructureParserTest do
  use ExUnit.Case

  alias Membrane.Core.Parent.{Link, StructureParser}
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

    assert {[], links} = StructureParser.parse(links_spec)

    assert [
             %Link{
               from: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :a},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :b},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :b},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :c},
                 pad_props: %{options: [q: 1]},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :c},
                 pad_props: %{},
                 pad_spec: :x,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :d},
                 pad_props: %{},
                 pad_spec: Pad.ref(:y, 2),
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :d},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, {Membrane.Bin, :itself}},
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
                 child: {:__membrane_full_child_name__, nil, :a},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :b},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :b},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :c},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :d},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :b},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :b},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_full_child_name__, nil, :e},
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

    links_spec = [child(:a, A) |> child(:b, A) |> child(:c, A)]
    assert {children, links} = StructureParser.parse(links_spec)

    assert [
             %Link{
               from: %Endpoint{
                 child: {:__membrane_incomplete_child_name__, :a},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_incomplete_child_name__, :b},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 child: {:__membrane_incomplete_child_name__, :b},
                 pad_props: %{},
                 pad_spec: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 child: {:__membrane_incomplete_child_name__, :c},
                 pad_props: %{},
                 pad_spec: :input,
                 pad_ref: nil,
                 pid: nil
               }
             }
           ] = links

    assert Enum.sort(children) == [
             {{:__membrane_incomplete_child_name__, :a}, A, %{get_if_exists: false}},
             {{:__membrane_incomplete_child_name__, :b}, A, %{get_if_exists: false}},
             {{:__membrane_incomplete_child_name__, :c}, A, %{get_if_exists: false}}
           ]
  end
end
