# Membrane Multimedia Framework

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_core.svg)](https://hex.pm/packages/membrane_core)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_core/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane-core.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane-core)

> Membrane Framework - if you asked me what it is, I have no idea. _- Jose Valim in [ElixirConf 2018 Keynote](https://www.youtube.com/watch?v=m7TWMFtDwHg&feature=youtu.be&t=11m18s)_

Multimedia processing framework that focuses on reliability, concurrency and scalability.

An easy to use abstraction layer for assembling mostly server-side applications that have to consume, produce or process multimedia streams.

It puts reliability over amount of features.

It is written in Elixir + C with outstanding Erlang VM underneath that gives us a rock solid and battle tested foundation.

## Membrane Core

This package provides core of the [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

Add the following line to your `deps` in `mix.exs`.  Run `mix deps.get`.

```elixir
{:membrane_core, "~> 0.5.2"}
```

## Getting started

To get familiar with basic concepts and build your first application using Membrane Framework, visit [Membrane Guide](https://membraneframework.org/guide).

API documentation is available at [HexDocs](https://hexdocs.pm/membrane_core/)

## Erlang/OTP 23 compatibility

It is not recommended currently to use Membrane with Erlang/OTP 23 due to [ERL-1273](https://bugs.erlang.org/browse/ERL-1273) that blocks compilation of some elements on Linux and macOS ([membraneframework/bundlex#58](https://github.com/membraneframework/bundlex/issues/58)). Erlang/OTP 22 is confirmed not to exhibit this bug.

## Support and questions

If you have any problems with Membrane Framework feel free to contact us via [membrane tag at Elixir forum](https://elixirforum.com/tag/membrane), [mailing list](https://groups.google.com/forum/#!forum/membrane-framework), [Discord](https://discord.gg/nwnfVSY) or via [e-mail](mailto:info@membraneframework.org).

## Copyright and License

Copyright 2018, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://membraneframework.github.io/static/logo/swm_logo_readme.png)](
https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
