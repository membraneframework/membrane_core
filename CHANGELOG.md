# Changelog

## Latest
* Improve remove_link action docs
* Add Mix tasks for easier initialization of components [#1059](https://github.com/membraneframework/membrane_core/pull/1059)

## 1.2.6
 * Add tutorials [#1007](https://github.com/membraneframework/membrane_core/pull/1007), plugins [#1012](https://github.com/membraneframework/membrane_core/pull/1012) and demos [#1013](https://github.com/membraneframework/membrane_core/pull/1013) to the docs.
 * Avoid division by 0 in stalker under weird timer behaviour [#1035](https://github.com/membraneframework/membrane_core/pull/1035)


## 1.2.5
_Release retired, please use 1.2.6_

## 1.2.4
 * Add `:handle_end_of_stream` and `:handle_start_of_stream` options to debug elements. [#993](https://github.com/membraneframework/membrane_core/pull/993)

## 1.2.3
 * Deprecate calling a children group `nil` in [#964](https://github.com/membraneframework/membrane_core/pull/964)
 * Adds new fields for the handle_child_terminated context: crash_initiator, exit_reason and group_name in [#964](https://github.com/membraneframework/membrane_core/pull/964)
 * Makes sure that all handle_child_terminated callbacks for children in crash group are called before handle_crash_group_down of that group in [#962](https://github.com/membraneframework/membrane_core/pull/962)
 * Telemetry event's metadata `component_type` now correctly refers to the root type and not the implementing module [#958](https://github.com/membraneframework/membrane_core/pull/958)

## 1.2.2
 * Improve conditions for generating compilation warnings. [#956](https://github.com/membraneframework/membrane_core/pull/956)

## 1.2.1
 * Improve stream format error. [#950](https://github.com/membraneframework/membrane_core/pull/950)
 * Minor fixes in `Membrane.Connector`. [#952](https://github.com/membraneframework/membrane_core/pull/952)

## 1.2.0
 * Add `:max_instances` option for dynamic pads. [#876](https://github.com/membraneframework/membrane_core/pull/876)
 * Implement `Membrane.Connector`. [#904](https://github.com/membraneframework/membrane_core/pull/904)
 * Implememnt diamonds detection. [#909](https://github.com/membraneframework/membrane_core/pull/909)
 * Incorporate `Membrane.Funnel`, `Membrane.Tee` and `Membane.Fake.Sink`. [#922](https://github.com/membraneframework/membrane_core/issues/922)
 * Added new, revised Telemetry system [#905](https://github.com/membraneframework/membrane_core/pull/918)

## 1.1.2
 * Add new callback `handle_child_terminated/3` along with new assertions. [#894](https://github.com/membraneframework/membrane_core/pull/894)
 * Remove 'failed to insert a metric' stalker warning. [#849](https://github.com/membraneframework/membrane_core/pull/849)

## 1.1.1
 * Fix 'table identifier does not refer to an existing ETS table' error when inserting metrics into the observability ETS. [#835](https://github.com/membraneframework/membrane_core/pull/835)
 * Fix bug occuring in distributed atomic implementation. [#837](https://github.com/membraneframework/membrane_core/pull/837)

## 1.1.0
 * Add new callbacks `handle_child_setup_completed/3` and `handle_child_playing/3` in Bins and Pipelines. [#801](https://github.com/membraneframework/membrane_core/pull/801)
 * Deprecate `handle_spec_started/3` callback in Bins and Pipelines. [#708](https://github.com/membraneframework/membrane_core/pull/708)
 * Handle buffers from input pads having `flow_control: :auto` only if demand on all output pads having `flow_control: :auto` is positive. [#693](https://github.com/membraneframework/membrane_core/pull/693)
 * Set `:ratio` dependency version to `"~> 3.0 or ~> 4.0"`. [#780](https://github.com/membraneframework/membrane_core/pull/780)
 * Deprecate `Membrane.Testing.Pipeline.message_child/3`. Introduce `Membrane.Testing.Pipeline.notify_child/3` instead. [#779](https://github.com/membraneframework/membrane_core/pull/779)

## 1.0.1
 * Specify the order in which state fields will be printed in the error logs. [#614](https://github.com/membraneframework/membrane_core/pull/614)
 * Fix clock selection [#626](https://github.com/membraneframework/membrane_core/pull/626)
 * Log messages in the default handle_info implementation [#680](https://github.com/membraneframework/membrane_core/pull/680)
 * Fix typespecs in Membrane.UtilitySupervisor [#681](https://github.com/membraneframework/membrane_core/pull/681)
 * Improve callback return types and group actions types [#702](https://github.com/membraneframework/membrane_core/pull/702) 
 * Add `crash_reason` to `handle_crash_group_down/3` callback context in bins and pipelines. [#720](https://github.com/membraneframework/membrane_core/pull/720)

## 1.0.0
 * Introduce `:remove_link` action in pipelines and bins.
 * Add children groups - a mechanism that allows refering to multiple children with a single identifier. 
 * Rename `remove_child` action into `remove_children` and allow for removing a children group with a single action.
 * Add an ability to spawn anonymous children.
 * Replace `Membrane.Time.round_to_<unit_name>` with `Membrane.Time.as_<unit_name>/2` with second argument equal `:round`. Rename `Membrane.Time.round_to_timebase` to `Membrane.Time.divide_by_timebase/2`. [#494](https://github.com/membraneframework/membrane_core/pull/494)
 * Remove `:playback` action. Introduce `:setup` action. [#496](https://github.com/membraneframework/membrane_core/pull/496)
 * Add `Membrane.Testing.Pipeline.get_child_pid/2`. [#497](https://github.com/membraneframework/membrane_core/pull/497)
 * Make callback contexts to be maps. [#504](https://github.com/membraneframework/membrane_core/pull/504)
 * All Membrane Elements can be compatible till now on - pads working in `:pull` mode, handling different `demand_units`, can be now linked.
 * Output pads working in `:pull` mode should have their `demand_unit` specified. If case it's not available, it's assumed that the pad handles demands in both `:bytes` and `:buffers` units.
 * Rename callbacks `handle_process/4` and `handle_write/4` to `handle_buffer/4` in [#506](https://github.com/membraneframework/membrane_core/pull/506)
 * The flow control of the pad is now set with a single `:flow_control` option instead of `:mode` and `:demand_mode` options.
 * Remove _t suffix from types [#509](https://github.com/membraneframework/membrane_core/pull/509)
 * Implement automatic demands in Membrane Sinks and Endpoints. [#512](https://github.com/membraneframework/membrane_core/pull/512)
 * Add `handle_child_pad_removed/4` callback in Bins and Pipelines. [#513](https://github.com/membraneframework/membrane_core/pull/513)
 * Introduce support for crash groups in Bins. [#521](https://github.com/membraneframework/membrane_core/pull/521)
 * Remove `assert_pipeline_play/2` from `Membrane.Testing.Assertions`. [#528](https://github.com/membraneframework/membrane_core/pull/528)
 * Make sure enumerable with all elements being `Membrane.Buffer.t()`, passed as `:output` parameter for `Membrane.Testing.Source` won't get rewrapped in `Membrane.Buffer.t()` struct.
 * Implement `Membrane.Debug.Filter` and `Membrane.Debug.Sink`. [#552](https://github.com/membraneframework/membrane_core/pull/552)
 * Add `:pause_auto_demand` and `:resume_auto_demand` actions. [#586](https://github.com/membraneframework/membrane_core/pull/586)
 * Send `:end_of_stream`, even if it is not preceded by `:start_of_stream`. [#557](https://github.com/membraneframework/membrane_core/pull/577)
 * Fix process leak in starting clocks. [#594](https://github.com/membraneframework/membrane_core/pull/594)
 * Add child exit reason to the supervisor exit reason. [#595](https://github.com/membraneframework/membrane_core/pull/595)
 * Remove default implementation of `start_/2`, `start_link/2` and `terminate/2` in modules using `Membrane.Pipeline`. [#598](https://github.com/membraneframework/membrane_core/pull/598) 
 * Remove callback _Membrane.Element.WithInputPads.handle_buffers_batch/4_. [#601](https://github.com/membraneframework/membrane_core/pull/601)
 * Sort component state fields in the error logs in the order from the most to the least important. [#614](https://github.com/membraneframework/membrane_core/pull/614)
 
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
 * Delete `:ok` from tuples returned from callbacks.
 * Remove `:type` from specs passed to `def_options/1` macro in bins and elements.
 * Add `Membrane.Testing.MockResourceGuard`.

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
