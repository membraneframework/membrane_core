# Upgrading to v0.11

v0.11 is a release with a lot of improvements and breaking changes, that haven't been introduced during earlier releases, so we decided to create this guide, to let you know, what changes will be introduced, and how to modify your existing code, to adjust to them.

## Deps ugrade

Update `membrane_core` to `v0.11`
```elixir 
defp deps do
   [
     {:membrane_core, "~> 0.11.0"},
     ...
   ]
end
```

## Actions

The following actions have changed their names:
 * `:caps` -> `:stream_format`

## Callbacks

The following callbacks have changed their names:
 * `handle_caps/4` -> `handle_stream_format/4`

## Pads definitions

In `v0.11` `:caps` option passed to `def_input_pad/2` or `def_output_pad/2` has been deleted. Instead of it, we have added new option - `:accepted_format`. The main principle of these two options is the same - validation of value passed to `:caps` or `:stream_format` action. While `:caps` required module name or specific tuple format as argument, `:accepted_format` requires following types of terms:

  * Elixir pattern - eg. `accepted_format: %My.Custom.Format{field: value} when value in [:some, :enumeration]`

    Value passed to `:stream_format` action has to match provided pattern. In this case, requirement above would 
    be satisfied by eg. `stream_format: %My.Custom.Format{field: :some}`

  * Module name - eg. `accepted_format: My.Custom.Format`
    This would be equal to match on struct of passed module, in this case `accepted_format: %My.Custom.Format{}`

  * Call to `any_of` function - you can pass as many arguments to it, as you want. Each argment should be Elixir pattern 
    or a module name, eg. `stream_format: any_of(My.Custom.Format, %My.Another.Custom.Format{field: :value})`

    If you use `any_of`, value passed to `:stream_format` will have to match to at least one of passed 
    arguments. In this case, `stream_format: %My.Custom.Format{frequency: 1}` would be ok, but 
    `stream_format: %My.Another.Custom.Format{field: :not_allowed_value}` would fail

Option `:accepted_format` is required. If you don't want to perform any check on `stream_format`, you can always write `accepted_format: _any`, but it is not suggested. 

Checks on `stream_format` will be performed on both, `intput` and `output` pads, just as `caps` were checked in those places. 
