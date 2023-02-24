# Changelog

# 0.11.3
 * Fix bug in `c:Membrane.Pipeline.handle_call/3` [#526](https://github.com/membraneframework/membrane_core/pull/526).

# 0.11.2
 * Fix bug in Membrane.ChildrenSpec.child/3 spec.

# 0.11.1
 * Fix subprocess supervisor crash when a child fails in handle_init [#488](https://github.com/membraneframework/membrane_core/pull/488)
 * Fix bug in pads docs generation [#490](https://github.com/membraneframework/membrane_core/pull/490)
 * Fix a deadlock when pipeline spawns a spec entailing two dependent specs in a bin [#484](https://github.com/membraneframework/membrane_core/pull/484)
 * Implement running all cleanup functions in ResourceGuard [#477](https://github.com/membraneframework/membrane_core/pull/477)
 * Stop all timers, when componenet enters zombie mode [#485](https://github.com/membraneframework/membrane_core/pull/485)

## 0.11.0
 * Separate element_name and pad arguments in handle_element_{start, end}_of_stream signature [#219](https://github.com/membraneframework/membrane_core/issues/219)
 * Refine communication between parent and its children [#270](https://github.com/membraneframework/membrane_core/issues/270)
 * Add `handle_call/3` callback in the pipeline, as well as a `:reply` and `:reply_to` actions. Rename `handle_other/3` callback into `handle_info/3` [#334](https://github.com/membraneframework/membrane_core/issues/334)
 * Add `Membrane.FilterAggregator` that allows to run multiple filters sequentially within one process. [#355](https://github.com/membraneframework/membrane_core/pull/355)
 * Log info about element's playback state change as debug, not as debug_verbose. [#430](https://github.com/membraneframework/membrane_core/pull/430)
 * Rename `Membrane.Time.to_<unit name>/1` into `Membrane.Time.round_to_<unit name>/1` to indicate that the result will be rounded. Make `Membrane.Time.<plural unit name>/1` accept `%Ratio{}` as an argument. Add `Membrane.Time.round_to_timebase/2` function.
 * New `spec` action syntax - the structure of pipeline is now defined with the use of `Membrane.ChildrenSpec`
 * Rename `:caps` to `:stream_format`.
 * Use Elixir patterns as `:accepted_format` in pad definition.
 * Delete `:ok` from tuples returned from callbacks 
 * Remove `:type` from specs passed to `def_options/1` macro in bins and elements.  
 * Add `Membrane.Testing.MockResourceGuard`

## 0.10.0
 * Remove all deprecated stuff [#399](https://github.com/membraneframework/membrane_core/pull/399)
 * Make `Membrane.Pipeline.{prepare, play, stop}` deprecated and add `:playback` action instead
 * Make `Membrane.Pipeline.stop_and_terminate` deprecated and add `Membrane.Pipeline.terminate/2` instead
 * Add `Membrane.RemoteControlled.Pipeline` - a basic implementation of a `Membrane.Pipeline` that </br>
   can be spawned and controlled by an external process [#366](https://github.com/membraneframework/membrane_core/pull/366)
 * Disallow sending buffers without sending caps first [#341](https://github.com/membraneframework/membrane_core/issues/341)
 * Refine the `Membrane.Testing.Pipeline` API - deprecate the `Membrane.Testing.Pipeline.Options` usage, use keyword list as options in `Membrane.Testing.Pipeline.start/1` and `Membrane.Testing.Pipeline.start_link/1`

## 0.9.0
 * Automatic demands [#313](https://github.com/membraneframework/membrane_core/pull/313)
 * Stop forwarding notifications by default in bins [#358](https://github.com/membraneframework/membrane_core/pull/358)
 * More fine-grained control over emitted metrics [#365](https://github.com/membraneframework/membrane_core/pull/365)

 ### PRs not influencing public API:
 * Added log metadata when reporting init in telemetry [#376](https://github.com/membraneframework/membrane_core/pull/376)
 * Fix generation of pad documentation inside an element [#377](https://github.com/membraneframework/membrane_core/pull/377)
 * Leaving static pads unlinked and transiting to a playback state other than `:stopped` will result
 in runtime error (previously only a warning was printed out). [#389](https://github.com/membraneframework/membrane_core/pull/389)
 * It is possible now to assert on crash group down when using Testing.Pipeline. [#391](https://github.com/membraneframework/membrane_core/pull/391)

## 0.8.2
 * Fixed PadAdded spec [#359](https://github.com/membraneframework/membrane_core/pull/359)
### PRs not influencing public API:
 * Prevent internal testing notifications from reaching pipeline module [#350](https://github.com/membraneframework/membrane_core/pull/350)
 * Fix unknown node error on distribution changes [#352](https://github.com/membraneframework/membrane_core/pull/352)
 * Add new type of element, `Membrane.Endpoint` [#382](https://github.com/membraneframework/membrane_core/pull/382)

## 0.8.1
 * allow telemetry in version 1.0 only [#347](https://github.com/membraneframework/membrane_core/pull/347)
### PRs not influencing public API:
 * fix action enforcing CHANGELOG update with PR [#345](https://github.com/membraneframework/membrane_core/pull/345)
 * Release membrane_core v0.8.1 [#348](https://github.com/membraneframework/membrane_core/pull/348)

## 0.8.0
### Release notes:
  * PTS and DTS timestamps were added to `Membrane.Buffer` structure explicitly. Timestamps should no longer live in `Membrane.Buffer.metadata` field [#335](https://github.com/membraneframework/membrane_core/pull/335).

### PRs not influencing public API:
  * add CHANGELOG update verification [#340](https://github.com/membraneframework/membrane_core/pull/340)
  * action enforcing changelog fix [#342](https://github.com/membraneframework/membrane_core/pull/342)
  * bump version to 0.8.0 [#344](https://github.com/membraneframework/membrane_core/pull/344)
