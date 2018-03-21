locals_without_parens = [
  def_known_source_pads: 1,
  def_known_sink_pads: 1,
  def_options: 1
]

[
  inputs: [
    "{lib,spec,config}/**/*.{ex,exs}",
    "mix.exs"
  ],
  import: [:espec],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]

