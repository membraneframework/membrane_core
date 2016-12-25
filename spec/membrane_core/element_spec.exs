defmodule Membrane.ElementSpec do
  use ESpec, async: true

  pending ".start_link/3"
  pending ".start/3"


  describe ".get_module/1" do
    context "if given pid is for element process" do
      let_ok :server, do: Membrane.Element.start(module, %{})
      finally do: Process.exit(server, :kill)

      context "if given pid is a source element" do
        let :module, do: Membrane.Support.Element.TrivialSource

        it "should return an ok result" do
          expect(described_module.get_module(server)).to be_ok_result
        end

        it "should return a module that was used to spawn the process" do
          {:ok, returned_module} = described_module.get_module(server)
          expect(returned_module).to eq module
        end
      end

      context "if given pid is a sink element" do
        let :module, do: Membrane.Support.Element.TrivialSink

        it "should return an ok result" do
          expect(described_module.get_module(server)).to be_ok_result
        end

        it "should return a module that was used to spawn the process" do
          {:ok, returned_module} = described_module.get_module(server)
          expect(returned_module).to eq module
        end
      end

      context "if given pid is a filter element" do
        let :module, do: Membrane.Support.Element.TrivialFilter

        it "should return an ok result" do
          expect(described_module.get_module(server)).to be_ok_result
        end

        it "should return a module that was used to spawn the process" do
          {:ok, returned_module} = described_module.get_module(server)
          expect(returned_module).to eq module
        end
      end
    end

    context "if given pid is not for element process" do
      it "should return an error result" do
        expect(described_module.get_module(self())).to be_error_result
      end

      it "should return :invalid as a reason" do
        {:error, reason} = described_module.get_module(self())
        expect(reason).to eq :invalid
      end
    end
  end


  describe ".get_module!/1" do
    context "if given pid is for element process" do
      let_ok :server, do: Membrane.Element.start(module, %{})
      finally do: Process.exit(server, :kill)

      context "if given pid is a source element" do
        let :module, do: Membrane.Support.Element.TrivialSource

        it "should return a module that was used to spawn the process" do
          expect(described_module.get_module!(server)).to eq module
        end
      end

      context "if given pid is a sink element" do
        let :module, do: Membrane.Support.Element.TrivialSink

        it "should return a module that was used to spawn the process" do
          expect(described_module.get_module!(server)).to eq module
        end
      end

      context "if given pid is a filter element" do
        let :module, do: Membrane.Support.Element.TrivialFilter

        it "should return a module that was used to spawn the process" do
          expect(described_module.get_module!(server)).to eq module
        end
      end
    end

    context "if given pid is not for element process" do
      it "should return :invalid as a reason" do
        expect(fn -> described_module.get_module!(self()) end).to throw_term(:invalid)
      end
    end
  end


  describe ".is_source?/1" do
    context "if given element is a source" do
      let :module, do: Membrane.Support.Element.TrivialSource

      it "should return true" do
        expect(described_module.is_source?(module)).to be_true
      end
    end

    context "if given element is a filter" do
      let :module, do: Membrane.Support.Element.TrivialFilter

      it "should return true" do
        expect(described_module.is_source?(module)).to be_true
      end
    end

    context "if given element is a sink" do
      let :module, do: Membrane.Support.Element.TrivialSink

      it "should return false" do
        expect(described_module.is_source?(module)).to be_false
      end
    end
  end


  describe ".is_sink?/1" do
    context "if given element is a source" do
      let :module, do: Membrane.Support.Element.TrivialSource

      it "should return false" do
        expect(described_module.is_sink?(module)).to be_false
      end
    end

    context "if given element is a filter" do
      let :module, do: Membrane.Support.Element.TrivialFilter

      it "should return true" do
        expect(described_module.is_sink?(module)).to be_true
      end
    end

    context "if given element is a sink" do
      let :module, do: Membrane.Support.Element.TrivialSink

      it "should return true" do
        expect(described_module.is_sink?(module)).to be_true
      end
    end
  end


  pending ".prepare/2"
  pending ".play/2"
  pending ".stop/2"


  describe ".link/2" do
    context "if first given PID is not a PID of an element process" do
      let :server, do: self()

      let_ok :destination, do: Membrane.Element.start(Membrane.Support.Element.TrivialSink, %{})
      finally do: Process.exit(destination, :kill)

      it "should return an error result" do
        expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
      end

      it "should return :invalid_element as a reason" do
        {:error, reason} = described_module.link({server, :source}, {destination, :sink})
        expect(reason).to eq :invalid_element
      end
    end

    context "if second given PID is not a PID of an element process" do
      let_ok :server, do: Membrane.Element.start(Membrane.Support.Element.TrivialSink, %{})
      finally do: Process.exit(server, :kill)

      let :destination, do: self()

      it "should return an error result" do
        expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
      end

      it "should return :invalid_element as a reason" do
        {:error, reason} = described_module.link({server, :source}, {destination, :sink})
        expect(reason).to eq :invalid_element
      end
    end


    context "if both given PIDs are equal" do
      let :server, do: self()
      let :destination, do: self()

      it "should return an error result" do
        expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
      end

      it "should return :loop as a reason" do
        {:error, reason} = described_module.link({server, :source}, {destination, :sink})
        expect(reason).to eq :loop
      end
    end


    context "if both given PIDs are PIDs of element processes" do
      let_ok :server, do: Membrane.Element.start(server_module, %{})
      finally do: Process.exit(server, :kill)

      let_ok :destination, do: Membrane.Element.start(destination_module, %{})
      finally do: Process.unlink(destination)

      context "but first given PID is not a source" do
        let :server_module, do: Membrane.Support.Element.TrivialSink
        let :destination_module, do: Membrane.Support.Element.TrivialSink

        it "should return an error result" do
          expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
        end

        it "should return :invalid_direction as a reason" do
          {:error, reason} = described_module.link({server, :source}, {destination, :sink})
          expect(reason).to eq :invalid_direction
        end
      end

      context "but second given PID is not a sink" do
        let :server_module, do: Membrane.Support.Element.TrivialSource
        let :destination_module, do: Membrane.Support.Element.TrivialSource

        it "should return an error result" do
          expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
        end

        it "should return :invalid_direction as a reason" do
          {:error, reason} = described_module.link({server, :source}, {destination, :sink})
          expect(reason).to eq :invalid_direction
        end
      end

      context "and first given PID is a source and second given PID is a sink" do
        let :server_module, do: Membrane.Support.Element.TrivialSource
        let :destination_module, do: Membrane.Support.Element.TrivialSink

        # TODO check if pads are present
        # TODO check if pads match at all
        # TODO check if pads are not already linked
      end
    end
  end


  pending ".link/3"
end
