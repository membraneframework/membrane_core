# Membrane Multimedia Framework

Multimedia processing framework that focuses on reliability, concurrency and scalability.

An easy to use abstraction layer for assembling mostly server-side applications that have to consume, produce or process multimedia streams.

It puts reliability over amount of features.

It is written in Elixir + C with outstanding Erlang VM underneath that gives us a rock solid and battle tested foundation.

# Membrane Core

This package provides core of the Membrane multimedia framework.


## Installation

Add the following line to your `deps` in `mix.exs`.  Run `mix deps.get`.

```elixir
{:membrane_core, git: "git@github.com:membraneframework/membrane-core.git"}
```

Then add the following line to your `applications` in `mix.exs`.

```elixir
:membrane_core
```

# Getting started

To get familiar with basic concepts and build your first application using Membrane Framework, visit [Membrane Guide](https://membraneframework.org/guide).

API documentation is available on [HexDocs](https://hexdocs.pm/membrane_core)

# Support and questions

If you have any problems with Membrane Framework feel free to contact us on the [mailing list](https://groups.google.com/forum/#!forum/membrane-framework)



# Copyright and License

Copyright 2018, Software Mansion

Licensed under the [Apache License, Version 2.0](LICENSE)
