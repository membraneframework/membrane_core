 ## 0.9.0
 * More fine-grained control over emitted metrics [#365](https://github.com/membraneframework/membrane_core/pull/365)
 * Added log metadata when reporting init/terminate in telemetry [#376](https://github.com/membraneframework/membrane_core/pull/376)

## 0.8.2
 * Fixed PadAdded spec [#359](https://github.com/membraneframework/membrane_core/pull/359)
### PRs not influencing public API:
 * Prevent internal testing notifications from reaching pipeline module [#350](https://github.com/membraneframework/membrane_core/pull/350)
 * Fix unknown node error on distribution changes [#352](https://github.com/membraneframework/membrane_core/pull/352)

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
