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

## Update callbacks

To update callbacks
  * rename `handle_caps/4` on `handle_stream_format/4`
  * ...

```diff
- def handle_caps(pad_ref, caps, ctx, state) do
+ def handle_stream_format(pad_ref, stream_format, ctx, state) do
```

## Update actions returned from callbacks

To update actions, rename:
  * `:caps` -> `:stream_format`
  * ...

```diff
- {{:ok, caps: %My.Format{freq: 1}}, state}
+ {{:ok, stream_format: %My.Format{freq: 1}}, state}
```

## Update pads definitions

Instead of using `:caps`, use `:accepted_format` option.
Option `:accepted_format` is able to receive:

 * Module name

```diff
- caps: My.Format
+ accepted_format: My.Format 
```

 * Elixir pattern

```diff
- caps: {My.Format, field: one_of([:some, :enumeration])}
+ accepted_format: %My.Format{field: value} when value in [:some, :enumeration]
```

```diff
- caps: :any
+ accepted_format: _any
```

 * Call to `any_of` function. You can pass there as many arguments, as you want. Each argment should be Elixir pattern or a module name

```diff
- caps: [My.Format, My.Another.Format]
+ accepted_format: any_of(My.Format, My.Another.Format)
```

```diff
- caps: [My.Format, {My.Another.Format, field: :strict_value}, My.Yet.Another.Format]
+ accepted_format: any_of(My.Format, %My.Another.Format{field: :strict_value}, My.Yet.Another.Format)
```

## Update options definitions

Remove `:type` key and related value from defined options. Add `:spec` instead, if it haven't been added before, and proper `:inspector`, if option has default value, that shouldn't be inspected by `inspect/1` during generating docs.

```diff 
- def_options tick_interval: [
-                 type: :time, 
-                 default: Membrane.Time.seconds(1)
-             ],
-             process: [
-                 type: :pid
-             ]
+ def_options tick_interval: [
+                 spec: Membrane.Time.t(),
+                 default: Membrane.Time.seconds(1),
+                 inspector: &Membrane.Time.inspect/1
+             ],
+             process: [
+                 spec: pid()
+             ] 
```