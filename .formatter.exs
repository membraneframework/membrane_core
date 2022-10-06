locals_without_parens =
  [
    def_output_pad: 2,
    def_input_pad: 2,
    def_options: 1,
    def_clock: 1,
    def_type_from_list: 1,
    assert_receive_message: 3
  ]

[
  inputs: [
    "{lib,test,config}/**/*.{ex,exs}",
    "mix.exs"
  ],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
