locals_without_parens = [
  def_known_source_pads: 1,
  def_known_sink_pads: 1,
  def_options: 1,
  def_type_from_list: 1
]

[
  inputs: [
    "{lib,config}/**/*.{ex,exs}",
    "mix.exs"
  ],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
