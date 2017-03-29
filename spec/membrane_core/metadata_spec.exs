defmodule Membrane.Buffer.MetadataSpec do
  use ESpec, async: true
  alias Membrane.Buffer.Metadata

  describe ".new/0" do
    it "should return empty map" do
      expect(described_module().new()).to eq Map.new
    end
  end


  describe ".update/3" do
    context "when key already exists in meta" do
      let :key,   do: :k
      let :meta,  do: Metadata.new |> Metadata.put(key(), :old_val)

      it "should return map" do
        expect(described_module().update(meta(), key(), :new_val)).to be_map()
      end

      it "should override old value" do
        %{k: new_val} = described_module().update(meta(), key(), :new_val)
        expect(new_val).to eq :new_val
      end
    end

    context "when key doesn't exist in meta" do
      let :meta,  do: Metadata.new |> Metadata.put(:other_key, :val)
      let :key,   do: :k

      it "should keep meta unchanged" do
        ret = described_module().update(meta(), key(), :val)
        expect(ret).to eq meta()
      end
    end
  end


  describe ".has_key?/2" do
    context "when key exists in meta" do
      let :key,  do: :k
      let :meta, do: Metadata.new |> Metadata.put(key(), :old_val)

      it "should return true" do
        expect(described_module().has_key?(meta(), key())).to be_true()
      end
    end

    context "when key doesn't exist in meta" do
      let :key,  do: :k
      let :meta, do: Metadata.new

      it "should return false" do
        expect(described_module().has_key?(meta(), key())).to be_false()
      end
    end
  end


  describe ".delete/2" do
    let :key,  do: :k
    let :meta, do: Metadata.new |> Metadata.put(key(), :old_val)

    context "when key exists in meta" do
      it "should return map without deleted item" do
        ret = described_module().delete(meta(), key())
        expect(ret).to be_empty()
      end
    end

    context "when key doesn't exist in meta" do
      it "should keep meta unchanged" do
        expect(described_module().delete(meta(), :other_key)).to eq meta()
      end
    end
  end


  describe ".put/3" do
    context "when given key already exists in meta" do
      let :key,  do: :k
      let :meta, do: Metadata.new |> Metadata.put(key(), :old_val)

      it "should override old value" do
        %{k: new_val} = described_module().put(meta(), key(), :new_val)
        expect(new_val).to eq :new_val
      end
    end

    context "when given key doesn't exist in meta" do
      let :key,  do: :k2
      let :meta, do: Metadata.new |> Metadata.put(key(), :other_val)

      it "should add key and value to meta" do
        %{k: val} = described_module().put(meta(), :k, :val)
        expect(val).to eq :val
      end
    end
  end
end
