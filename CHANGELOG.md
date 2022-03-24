# Changelog

## 0.10.0
 * Remove all deprecated stuff [#399](https://github.com/membraneframework/membrane_core/pull/399)
 * Add `Membrane.RemoteControlled.Pipeline` - a basic implementation of a `Membrane.Pipeline` that </br> 
   can be spawned and controlled by an external process [#366](https://github.com/membraneframework/membrane_core/pull/366)  
 * Disallow sending buffers without sending caps first [#341](https://github.com/membraneframework/membrane_core/issues/341)
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
  * add CHANGELOG update verification #340
  * action enforcing changelog fix #342
  * bump version to 0.8.0 #344
