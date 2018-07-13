defmodule Membrane.Helper.RetrySpec do
  use ESpec, async: false

  describe ".retry/3" do
    let :times, do: 5
    let :delay, do: 1 |> Membrane.Time.millisecond()
    let :fun, do: &TestModule.func/0
    let :params, do: [times: times(), delay: delay()]

    context "when arbiter returns :finish" do
      before do: allow(TestModule).to(accept(:func, fn -> :ok end))

      let :arbiter, do: fn _ -> :finish end

      it "should call func only once" do
        described_module().retry(fun(), arbiter(), params())
        expect(TestModule |> to(accepted(:func, :any, count: 1)))
      end
    end

    context "when arbiter returns :retry" do
      before do: allow(TestModule).to(accept(:func, fn -> :ok end))
      let :arbiter, do: fn _ -> :retry end

      it "should call func `times() + 1` times" do
        described_module().retry(fun(), arbiter(), params())
        expect(TestModule |> to(accepted(:func, :any, count: times() + 1)))
      end
    end
  end
end
