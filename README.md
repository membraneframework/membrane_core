# Membrane Multimedia Framework: Core

This package provides core of the Membrane multimedia framework.


# Installation

Add the following line to your `deps` in `mix.exs`.  Run `mix deps.get`.

```elixir
{:membrane_core, git: "git@bitbucket.org:radiokit/membrane-core.git"}
```

Then add the following line to your `applications` in `mix.exs`.

```elixir
:membrane_core
```

# Documentation

Fetch the dependencies first:

```sh
mix deps.get
```

then you can generate documentation:

```sh
mix docs
```

HTML documentation will be built into `doc/` directory.


# Authors

* Marcin Lewandowski
