defmodule Membrane.Parent.LinkTest do
  use ExUnit.Case

  alias Membrane.Core.Parent.Link
  alias Membrane.Core.Parent.Link.Endpoint

  test "valid link" do
    import Membrane.ParentSpec

    links_spec = [
      link(:a)
      |> to(:b)
      |> via_in(:input, pad: [q: 1])
      |> to(:c)
      |> via_out(:x)
      |> via_in(:y, id: 2)
      |> to(:d)
      |> to_bin_output()
    ]

    assert {:ok, links} = Link.from_spec(links_spec)

    assert Enum.sort(links) == [
             %Link{
               from: %Endpoint{
                 element: :a,
                 id: nil,
                 opts: [],
                 pad_name: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 element: :b,
                 id: nil,
                 opts: [],
                 pad_name: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 element: :b,
                 id: nil,
                 opts: [],
                 pad_name: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 element: :c,
                 id: nil,
                 opts: [pad: [q: 1]],
                 pad_name: :input,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 element: :c,
                 id: nil,
                 opts: [],
                 pad_name: :x,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 element: :d,
                 id: 2,
                 opts: [],
                 pad_name: :y,
                 pad_ref: nil,
                 pid: nil
               }
             },
             %Link{
               from: %Endpoint{
                 element: :d,
                 id: nil,
                 opts: [],
                 pad_name: :output,
                 pad_ref: nil,
                 pid: nil
               },
               to: %Endpoint{
                 element: %Membrane.Bin.Itself{},
                 id: nil,
                 opts: [],
                 pad_name: :output,
                 pad_ref: nil,
                 pid: nil
               }
             }
           ]
  end

  test "invalid link" do
    [:abc, [:abc]]
    |> Enum.each(fn link_spec ->
      assert_raise Membrane.ParentError, ~r/.*Invalid links specification.*:abc/, fn ->
        Link.from_spec(link_spec)
      end
    end)
  end

  test "incomplete link" do
    import Membrane.ParentSpec

    %{
      :a => [link(:a)],
      :b => [link(:b) |> via_out(:x)],
      :c => [link(:c) |> via_in(:y)],
      %Membrane.Bin.Itself{} => [link_bin_input()]
    }
    |> Enum.each(fn {from, link_spec} ->
      assert_raise Membrane.ParentError,
                   ~r/.*link from #{inspect(from)} lacks its destination.*/,
                   fn -> Link.from_spec(link_spec) end
    end)
  end
end
