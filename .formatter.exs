# FIXME: remove and import from espec once released
espec_locals_without_parens = [
  ## Test setup
  before: 1,
  before_all: 1,
  after_all: 1,
  finally: 1,
  subject: :*,
  subject!: :*,
  let: :*,
  let!: :*,
  let_error: :*,
  let_error!: :*,
  let_ok: :*,
  let_ok!: :*,
  let_overridable: 1,

  ## Examples
  focus: :*,
  pending: 1,
  example: :*,
  it: :*,
  specify: :*,
  it_behaves_like: :*,

  ## Assertions / Matchers
  assert: 1,
  refute: 1,
  assert_receive: 3,
  assert_received: 2,
  refute_receive: 3,
  refute_received: 2,
  eq: 1,
  eql: 1,

  ### be_*
  be: :*,
  be_function: :*,
  be_between: 2,
  be_struct: 1,

  ### have_*
  have: 1,
  have_key: 1,
  have_value: 1,
  have_count: 1,
  have_first: 1,
  have_last: 1,

  ### match_*
  match_pattern: 1,
  match_list: 1,

  # String matchers
  start_with: 1,
  end_with: 1,

  ### Error matchers
  raise_exception: :*,

  ## Mocking / Stubbing
  allow: 1,
  accept: 2
]

locals_without_parens =
  [
    def_output_pad: 2,
    def_input_pad: 2,
    def_options: 1,
    def_clock: 1,
    def_type_from_list: 1,
    assert_receive_message: 3
  ] ++ espec_locals_without_parens

[
  inputs: [
    "{lib,spec,test,config}/**/*.{ex,exs}",
    "mix.exs"
  ],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
