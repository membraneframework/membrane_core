defmodule Membrane.Helper.BitstringSpec do
  use ESpec, async: true

  # These functions just wraps result of sample function used for specs in
  # the `{:ok, something}` return value.
  def sample_fun_upcase_ok_with_value(bitstring) do
    {:ok, String.upcase(bitstring)}
  end


  def sample_fun_upcase_ok_without_value(_bitstring) do
    :ok
  end


  def sample_fun_equivalent_ok_with_value?(bitstring1, bitstring2) do
    {:ok, String.equivalent?(bitstring1, bitstring2)}
  end


  def sample_fun_equivalent_ok_without_value?(_bitstring1, _bitstring2) do
    :ok
  end


  # These functions just wraps result of sample function used for specs in
  # the `{:error, something}` return value.
  def sample_fun_upcase_error_with_value("ab") do
    {:error, :something}
  end

  def sample_fun_upcase_error_with_value(bitstring) do
    {:ok, String.upcase(bitstring)}
  end


  def sample_fun_upcase_error_without_value("ab") do
    {:error, :something}
  end

  def sample_fun_upcase_error_without_value(_bitstring) do
    :ok
  end


  describe ".split_map/4" do
    let :data, do: "abcd"

    context "if at least one call to the processing function have returned an error" do
      let :process_fun, do: &sample_fun_upcase_error_with_value/1

      context "if there were no extra arguments passed" do
        let :extra_fun_args, do: []

        context "if given size allows to split given bitstring into parts without leaving any unprocessed bitstring" do
          let :size, do: 2

          it "should return an error result" do
            expect(described_module.split_map(data, size, process_fun, extra_fun_args)).to be_error_result
          end

          it "should return reason given by the processing function as a reason" do
            {:error, reason} = described_module.split_map(data, size, process_fun, extra_fun_args)
            expect(reason).to eq :something
          end
        end
      end
    end

    context "if no call to the processing function have returned an error" do
      let :process_fun, do: &sample_fun_upcase_ok_with_value/1

      context "if there were no extra arguments passed" do
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
        let :process_fun, do: &sample_fun_equivalent_ok_with_value?/2
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


  describe ".split_each/4" do
    let :data, do: "abcd"

    context "if at least one call to the processing function have returned an error" do
      let :process_fun, do: &sample_fun_upcase_error_without_value/1

      context "if there were no extra arguments passed" do
        let :extra_fun_args, do: []

        context "if given size allows to split given bitstring into parts without leaving any unprocessed bitstring" do
          let :size, do: 2

          it "should return an error result" do
            expect(described_module.split_each(data, size, process_fun, extra_fun_args)).to be_error_result
          end

          it "should return reason given by the processing function as a reason" do
            {:error, reason} = described_module.split_each(data, size, process_fun, extra_fun_args)
            expect(reason).to eq :something
          end
        end
      end
    end

    context "if no call to the processing function have returned an error" do
      let :process_fun, do: &sample_fun_upcase_ok_without_value/1

      context "if there were no extra arguments passed" do
        let :extra_fun_args, do: []

        context "if given size allows to split given bitstring into parts without leaving any unprocessed bitstring" do
          let :size, do: 2

          it "should return an ok result" do
            expect(described_module.split_each(data, size, process_fun, extra_fun_args)).to be_ok_result
          end

          it "should return an empty bitstring as remaining bitstring" do
            {:ok,rest} = described_module.split_each(data, size, process_fun, extra_fun_args)
            expect(rest).to eq << >>
          end
        end

        context "if given size does not allow to split given bitstring into parts without leaving any unprocessed bitstring" do
          let :size, do: 3

          it "should return an ok result" do
            expect(described_module.split_each(data, size, process_fun, extra_fun_args)).to be_ok_result
          end

          it "should return a unprocessed bitstring as remaining bitstring" do
            {:ok, rest} = described_module.split_each(data, size, process_fun, extra_fun_args)
            expect(rest).to eq "d"
          end
        end
      end

      context "if there were some arguments passed" do
        let :process_fun, do: &sample_fun_equivalent_ok_without_value?/2
        let :extra_fun_args, do: ["ab"]

        context "if given size allows to split given bitstring into parts without leaving any unprocessed bitstring" do
          let :size, do: 2

          it "should return an ok result" do
            expect(described_module.split_each(data, size, process_fun, extra_fun_args)).to be_ok_result
          end

          it "should return an empty bitstring as remaining bitstring" do
            {:ok, rest} = described_module.split_each(data, size, process_fun, extra_fun_args)
            expect(rest).to eq << >>
          end
        end

        context "if given size does not allow to split given bitstring into parts without leaving any unprocessed bitstring" do
          let :size, do: 3

          it "should return an ok result" do
            expect(described_module.split_each(data, size, process_fun, extra_fun_args)).to be_ok_result
          end

          it "should return a unprocessed bitstring as remaining bitstring" do
            {:ok, rest} = described_module.split_each(data, size, process_fun, extra_fun_args)
            expect(rest).to eq "d"
          end
        end
      end
    end
  end
end
