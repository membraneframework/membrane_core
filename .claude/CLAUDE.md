# Claude Instructions

This is the **membrane_core** repository — the core of the Membrane multimedia streaming framework for Elixir.

Always use the `membrane-core` skill when working in this repository.

## Running Tests

```bash
mix test                  # run all tests
mix coveralls             # with coverage
mix coveralls.html        # coverage as HTML report
```

## Project Structure

| Directory | Purpose |
|-----------|---------|
| `lib/` | Main source code |
| `test/` | Tests |
| `test/support/` | Test helpers |
| `guides/` | Documentation and tutorials |
| `benchmark/` | Performance benchmarks |
| `config/` | Configuration |

## Conventions

- Elixir ~> 1.17
- Format code with `mix format`
- Type checking via Dialyzer (`mix dialyzer`)
- Linting via Credo (`mix credo`)
- Never modify code in `deps/`
