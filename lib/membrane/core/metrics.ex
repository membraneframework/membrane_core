defmodule Membrane.Core.Metrics do
  if Application.compile_env(:membrane_core, :enable_metrics, false) do
    def init() do
      :ets.new(__MODULE__, [:named_table, :public, write_concurrency: true])
      :ok
    end

    defmacro report(metric, value, opts \\ []) do
      quote do
        :ets.insert(
          unquote(__MODULE__),
          {{unquote(metric), unquote(opts)[:component_path] || Membrane.ComponentPath.get(),
            unquote(opts)[:id]}, unquote(value)}
        )

        :ok
      end
    end

    defmacro report_update(metric, init, fun, opts \\ []) do
      quote do
        key =
          {unquote(metric), unquote(opts)[:component_path] || Membrane.ComponentPath.get(),
           unquote(opts)[:id]}

        [{_key, value} | _default] =
          :ets.lookup(unquote(__MODULE__), key) ++ [{nil, unquote(init)}]

        :ets.insert(unquote(__MODULE__), {key, unquote(fun).(value)})
      end
    end

    def scrape() do
      :ets.tab2list(__MODULE__)
    end
  else
    def init() do
      :ok
    end

    defmacro report(metric, value, opts \\ []) do
      quote do
        fn ->
          _unused = unquote(metric)
          _unused = unquote(value)
          _unused = unquote(opts)
        end

        :ok
      end
    end

    defmacro report_update(metric, init, fun, opts \\ []) do
      quote do
        fn ->
          _unused = unquote(metric)
          _unused = unquote(init)
          _unused = unquote(fun)
          _unused = unquote(opts)
        end

        :ok
      end
    end

    def scrape() do
      raise "Membrane Core metrics disabled"
    end
  end
end
