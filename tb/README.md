# DV README — runctl_mgmt_host

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_EDGE.md`, `DV_CROSS.md`, `DV_ERROR.md`, `DV_PROF.md`,
`BUG_HISTORY.md`

This directory holds standalone DV collateral for `runctl_mgmt_host`.

## Current implemented regressions

- `runctl_mgmt_host_smoke_test`
  - current log: `logs/runctl_mgmt_host_smoke_test.log`
  - current result: pass
- `runctl_mgmt_host_synclink_cmd_matrix_test`
  - current log: `logs/runctl_mgmt_host_synclink_cmd_matrix_test.log`
  - current result: pass
- `runctl_mgmt_host_swb_run_number_endian_test`
  - current log: `logs/runctl_mgmt_host_swb_run_number_endian_test.log`
  - current result: pass
  - canonical standalone regression for `BUG-003-R`
- `runctl_mgmt_host_local_cmd_backpressure_test`
  - current log: `logs/runctl_mgmt_host_local_cmd_backpressure_test.log`
  - current result: pass
  - canonical standalone regression for `BUG-001-R`

## Current scope note

The authored plan documents still describe a broader future bucket-library UVM
environment. The direct tests above are the currently implemented
standalone regressions in this tree and should be treated as the live evidence
set unless newer generated reports are added later.
