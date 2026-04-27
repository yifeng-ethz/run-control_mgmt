# DV PROF — runctl_mgmt_host

**Companion docs:** `README.md`, `DV_PLAN.md`, `DV_EDGE.md`,
`BUG_HISTORY.md`

This bucket is reserved for future long-run, sustained-backpressure, and
profile-based standalone DV cases.

## Current status

- no dedicated `PROF` sequence library or generated profile dashboard exists in
  this tree yet
- the active local-command backpressure regression lives in
  `runctl_mgmt_host_local_cmd_backpressure_test`
- the bug and repro history for that path is tracked in `BUG_HISTORY.md`

## Interim policy

Until a dedicated profile bucket is implemented, any long-run or stress case
that materially changes the signoff position should be recorded in
`BUG_HISTORY.md` and linked from the relevant authored plan section.
