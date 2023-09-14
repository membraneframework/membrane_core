# Changelog

# 0.12.9
 * Add `:pause_auto_demand` and `:resume_auto_demand` actions. [#586](https://github.com/membraneframework/membrane_core/pull/586)
 * Fix process leak in starting clocks. [#594](https://github.com/membraneframework/membrane_core/pull/594)
 * Add child exit reason to the supervisor exit reason. [#595](https://github.com/membraneframework/membrane_core/pull/595)

# 0.12.8
 * Fix race condition in links deletion. [#591](https://github.com/membraneframework/membrane_core/pull/591)
 * Improve error message, when stream format does not match the accepted format pattern. [#591](https://github.com/membraneframework/membrane_core/pull/591)
 * Fix bug in default pipeline functions specs. [#585](https://github.com/membraneframework/membrane_core/pull/585)

# 0.12.7
 * Fix bug in generating processes names. [#584](https://github.com/membraneframework/membrane_core/pull/584)
 * Fix bug in registering metrics. [#582](https://github.com/membraneframework/membrane_core/pull/582)
 * Improve error message on lack of `handle_child_pad_removed/4` callback implementation. [#581](https://github.com/membraneframework/membrane_core/pull/581)
 * Improve actions docs. [#580](https://github.com/membraneframework/membrane_core/pull/580)

# 0.12.6
 * Implement functionalities needed for integration with `membrane_kino_dashboard`. [#571](https://github.com/membraneframework/membrane_core/pull/571)

# 0.12.5
 * Fix compilation error occurring with Elixir 1.15. [#573](https://github.com/membraneframework/membrane_core/pull/573)

# 0.12.4
 * Fix compilation error occurring with Elixir 1.15. [#570](https://github.com/membraneframework/membrane_core/pull/570)

# 0.12.3
 * Fix bug in fields naming in callback contexts. [#569](https://github.com/membraneframework/membrane_core/pull/569)
 * Update exit reasons of Membrane Components and their supervisors. [#567](https://github.com/membraneframework/membrane_core/pull/567)

## 0.12.2
 * Fix bug in order of handling actions returned from callbacks.

## 0.12.1
 * Introduce `:remove_link` action in pipelines and bins.
 * Add children groups - a mechanism that allows refering to multiple children with a single identifier. 
 * Add an ability to spawn anonymous children.
 * Remove `:playback` action. Introduce `:setup` action. [#496](https://github.com/membraneframework/membrane_core/pull/496)
 * Add `Membrane.Testing.Pipeline.get_child_pid/2`. [#497](https://github.com/membraneframework/membrane_core/pull/497)
 * Make callback contexts to be maps. [#504](https://github.com/membraneframework/membrane_core/pull/504)
 * All Membrane Elements can be compatible till now on - pads working in `:pull` mode, handling different `demand_units`, can be now linked.
 * Output pads working in `:pull` mode should have their `demand_unit` specified. If case it's not available, it's assumed that the pad handles demands in both `:bytes` and `:buffers` units.
 * Remove _t suffix from types [#509](https://github.com/membraneframework/membrane_core/pull/509)
 * Implement automatic demands in Membrane Sinks and Endpoints. [#512](https://github.com/membraneframework/membrane_core/pull/512)
 * Add `handle_child_pad_removed/4` callback in Bins and Pipelines. [#513](https://github.com/membraneframework/membrane_core/pull/513)
 * Introduce support for crash groups in Bins. [#521](https://github.com/membraneframework/membrane_core/pull/521)
 * Make sure enumerable with all elements being `Membrane.Buffer.t()`, passed as `:output` parameter for `Membrane.Testing.Source` won't get rewrapped in `Membrane.Buffer.t()` struct.
 * Implement `Membrane.Debug.Filter` and `Membrane.Debug.Sink`. [#552](https://github.com/membraneframework/membrane_core/pull/552)
 * Add `:pause_auto_demand` and `:resume_auto_demand` actions. [#586](https://github.com/membraneframework/membrane_core/pull/586)
 * Fix process leak in starting clocks. [#594](https://github.com/membraneframework/membrane_core/pull/594)
 * Add child exit reason to the supervisor exit reason. [#595](https://github.com/membraneframework/membrane_core/pull/595)
 
## 0.11.0
 * Separate element_name and pad arguments in handle_element_{start, end}_of_stream signature [#219](https://github.com/membraneframework/membrane_core/issues/219)
 * Refine communication between parent and its children [#270](https://github.com/membraneframework/membrane_core/issues/270)
 * Add `handle_call/3` callback in the pipeline, as well as a `:reply` and `:reply_to` actions. Rename `handle_other/3` callback into `handle_info/3` [#334](https://github.com/membraneframework/membrane_core/issues/334)
 * Add `Membrane.FilterAggregator` that allows to run multiple filters sequentially within one process. [#355](https://github.com/membraneframework/membrane_core/pull/355)
 * Log info about element's playback state change as debug, not as debug_verbose. [#430](https://github.com/membraneframework/membrane_core/pull/430)
 * Rename `Membrane.Time.to_<unit name>/1` into `Membrane.Time.round_to_<unit name>/1` to indicate that the result will be rounded. Make `Membrane.Time.<plural unit name>/1` accept `%Ratio{}` as an argument. Add `Membrane.Time.round_to_timebase` function.
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
 * Add `Membrane.RemoteControlled.Pipeline` - a basic implementation of a `Membrane.Pipeline` that can be spawned and controlled by an external process [#366](https://github.com/membraneframework/membrane_core/pull/366)
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
