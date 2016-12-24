defmodule Membrane.Helper.BitstringSpec do
  use ESpec, async: true


  describe ".split_map/4" do
    let :data, do: "abcd"

    context "if there were no extra arguments passed" do
      let :process_fun, do: &String.upcase/1
      let :extra_fun_args, do: []

      context "if given size allows to split given bitstring into parts without leaving any unprocessed bitstring" do
        let :size, do: 2

        it "should return an ok result" do
          expect(described_module.split_map(data, size, process_fun, extra_fun_args)).to be_ok_result
        end

        it "should return a list of items that was processed using given function" do
          {:ok, {items, _rest}} = described_module.split_map(data, size, process_fun, extra_fun_args)
          expect(items).to eq ["AB", "CD"]
        end

        it "should return an empty bitstring as remaining bitstring" do
          {:ok, {_items, rest}} = described_module.split_map(data, size, process_fun, extra_fun_args)
          expect(rest).to eq << >>
        end
      end

      context "if given size does not allow to split given bitstring into parts without leaving any unprocessed bitstring" do
        let :size, do: 3

        it "should return an ok result" do
          expect(described_module.split_map(data, size, process_fun, extra_fun_args)).to be_ok_result
        end

        it "should return a list of items that was processed using given function" do
          {:ok, {items, _rest}} = described_module.split_map(data, size, process_fun, extra_fun_args)
          expect(items).to eq ["ABC"]
        end

        it "should return a unprocessed bitstring as remaining bitstring" do
          {:ok, {_items, rest}} = described_module.split_map(data, size, process_fun, extra_fun_args)
          expect(rest).to eq "d"
        end
      end
    end

    context "if there were some arguments passed" do
      let :process_fun, do: &String.equivalent?/2
      let :extra_fun_args, do: ["ab"]

      context "if given size allows to split given bitstring into parts without leaving any unprocessed bitstring" do
        let :size, do: 2

        it "should return an ok result" do
          expect(described_module.split_map(data, size, process_fun, extra_fun_args)).to be_ok_result
        end

        it "should return a list of items that was processed using given function" do
          {:ok, {items, _rest}} = described_module.split_map(data, size, process_fun, extra_fun_args)
          expect(items).to eq [true, false]
        end

        it "should return an empty bitstring as remaining bitstring" do
          {:ok, {_items, rest}} = described_module.split_map(data, size, process_fun, extra_fun_args)
          expect(rest).to eq << >>
        end
      end

      context "if given size does not allow to split given bitstring into parts without leaving any unprocessed bitstring" do
        let :size, do: 3

        it "should return an ok result" do
          expect(described_module.split_map(data, size, process_fun, extra_fun_args)).to be_ok_result
        end

        it "should return a list of items that was processed using given function" do
          {:ok, {items, _rest}} = described_module.split_map(data, size, process_fun, extra_fun_args)
          expect(items).to eq [false]
        end

        it "should return a unprocessed bitstring as remaining bitstring" do
          {:ok, {_items, rest}} = described_module.split_map(data, size, process_fun, extra_fun_args)
          expect(rest).to eq "d"
        end
      end
    end
  end
end
