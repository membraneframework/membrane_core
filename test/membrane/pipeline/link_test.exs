defmodule Membrane.Pipeline.LinkTest do
  use ExUnit.Case
  alias Membrane.Core.Link
  alias Link.Endpoint

  @moduletag :focus

  test "Endpoint parsing" do
    assert Endpoint.parse({:source, :input}) ==
             {:ok, %Endpoint{element: :source, pad_name: :input, opts: []}}

    assert Endpoint.parse({{:source, 42}, :input}) ==
             {:ok, %Endpoint{element: {:source, 42}, pad_name: :input, opts: []}}

    assert Endpoint.parse({:source, :input, pad: [mute: true]}) ==
             {:ok, %Endpoint{element: :source, pad_name: :input, opts: [pad: [mute: true]]}}

    assert Endpoint.parse({:source}) == {:error, {:invalid_endpoint, {:source}}}

    assert Endpoint.parse({:source, 42}) == {:error, {:invalid_pad_format, 42}}
  end

  def test_valid_link(raw_from, raw_to) do
    assert {:ok, %Link{from: from, to: to}} = Link.parse({raw_from, raw_to})
    assert {:ok, from} == Endpoint.parse(raw_from)
    assert {:ok, to} == Endpoint.parse(raw_to)
  end

  def test_invalid_link(raw_from, raw_to) do
    assert Link.parse({raw_from, raw_to}) == Endpoint.parse(raw_from)
  end

  test "Link parsing" do
    valid_end = {:source, :input}
    valid_end_opt = {:source, :input, pad: [mute: true]}
    invalid_end = {:source}
    invalid_pad = {:source, 42}

    test_valid_link(valid_end, valid_end)
    test_valid_link(valid_end_opt, valid_end)
    test_valid_link(valid_end, valid_end_opt)
    test_valid_link(valid_end_opt, valid_end_opt)

    assert Link.parse({invalid_end, valid_end}) == Endpoint.parse(invalid_end)
    assert Link.parse({valid_end, invalid_end}) == Endpoint.parse(invalid_end)

    assert Link.parse({invalid_pad, valid_end}) == Endpoint.parse(invalid_pad)
    assert Link.parse({valid_end, invalid_pad}) == Endpoint.parse(invalid_pad)

    not_link = {:not, :a, :link}
    assert Link.parse(not_link) == {:error, {:invalid_link, not_link}}
  end
end
