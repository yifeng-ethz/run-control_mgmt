# ⚠️ Signoff — runctl_mgmt_host

**DUT:** `runctl_mgmt_host` &nbsp; **Date:** `2026-04-22` &nbsp;
**Release under check:** `26.2.0.0416` plus local working-tree bug fix &nbsp;
**Git base:** `run-control_mgmt` `379e13a`

This page is the master signoff dashboard for the local `runctl_mgmt_host`
standalone IP. Detailed standalone synthesis evidence lives in
[`../syn/SYN_REPORT.md`](../syn/SYN_REPORT.md). Directed standalone DV evidence
and the bug ledger live in [`../tb/`](../tb/).

## Legend

✅ pass / closed &middot; ⚠️ partial / caveat &middot; ❌ failed / blocked &middot; ❓ pending &middot; ℹ️ informational

## Health

| status | field | value |
|:---:|---|---|
| ⚠️ | overall_signoff | `partial` |
| ✅ | standalone_timing_resources | last measured standalone Quartus fit closes timing and stays comfortably below any resource limit; see [`../syn/SYN_REPORT.md`](../syn/SYN_REPORT.md) |
| ✅ | standalone_direct_rtl_regression | `runctl_mgmt_host_smoke_test`, `runctl_mgmt_host_synclink_cmd_matrix_test`, and `runctl_mgmt_host_local_cmd_backpressure_test` all pass on `2026-04-22` |
| ⚠️ | standalone_gate_regression | not rerun after `BUG-001-R` |
| ⚠️ | authored_dv_catalog_closure | broader planned bucket-library catalog remains authored but not fully implemented |
| ✅ | bug_ledger | `BUG-001-R` is recorded with the live reproducer and fix status in [`../tb/BUG_HISTORY.md`](../tb/BUG_HISTORY.md) |

## Verification

| status | area | result | source |
|:---:|---|---|---|
| ✅ | standalone smoke | pass; scoreboard `runctl=3 upload=1 reset_events=3` | [`../tb/logs/runctl_mgmt_host_smoke_test.log`](../tb/logs/runctl_mgmt_host_smoke_test.log) |
| ✅ | standalone synclink command matrix | pass; scoreboard `runctl=9 upload=2 reset_events=2` | [`../tb/logs/runctl_mgmt_host_synclink_cmd_matrix_test.log`](../tb/logs/runctl_mgmt_host_synclink_cmd_matrix_test.log) |
| ✅ | local-command backpressure regression | pass; canonical direct regression for `BUG-001-R` | [`../tb/logs/runctl_mgmt_host_local_cmd_backpressure_test.log`](../tb/logs/runctl_mgmt_host_local_cmd_backpressure_test.log) |
| ⚠️ | full planned DV matrix | authored in `DV_PLAN.md` / `DV_EDGE.md`, but not yet promoted into a generated bucket dashboard | [`../tb/DV_PLAN.md`](../tb/DV_PLAN.md) |

## Synthesis

| status | item | value |
|:---:|---|---|
| ✅ | revision | `runctl_mgmt_host_syn` |
| ✅ | device | `5AGXBA7D4F31C5` |
| ✅ | measured timing | last standalone fit closes both `mm_clk` and `lvdspll_clk` signoff clocks across the reported corners |
| ✅ | fitted resources | `761 ALMs`, `1,599` registers, `4` RAM blocks |
| ⚠️ | refresh caveat | the functional `BUG-001-R` fix was verified in standalone RTL reruns on `2026-04-22`, but the standalone Quartus fit has not yet been rerun after that fix |
| ✅ | detail report | [`../syn/SYN_REPORT.md`](../syn/SYN_REPORT.md) |

## Fixes In Scope

| status | class | summary |
|:---:|---|---|
| ✅ | RTL | `BUG-001-R` is fixed in the local working tree: a held `LOCAL_CMD` Avalon write beat can no longer re-arm itself as a phantom second local command while the first command is still stalled on downstream ready |
| ✅ | DV | the new direct test `runctl_mgmt_host_local_cmd_backpressure_test` now captures the same stuck status that was previously seen in the live FEB probe and keeps that regression in the standalone suite |
| ⚠️ | collateral | authored plan/harness docs still describe a broader future bucket-library environment than the currently implemented direct-test suite |

## Evidence Index

- [`../tb/README.md`](../tb/README.md) — standalone DV entry point
- [`../tb/BUG_HISTORY.md`](../tb/BUG_HISTORY.md) — bug ledger
- [`../tb/DV_PLAN.md`](../tb/DV_PLAN.md) — authored standalone plan
- [`../syn/SYN_REPORT.md`](../syn/SYN_REPORT.md) — standalone synthesis report
- [`../doc/rtl_note.md`](rtl_note.md) — earlier standalone signoff note retained for history

## Notes

- The local bug was first seen on live FEB hardware and then reproduced in
  standalone QuestaOne sim before changing the RTL.
- The current signoff state is intentionally conservative: functional closure
  for the local-command wedge is green, but the matching standalone Quartus
  rerun and refreshed gate regression still need to be completed before the
  dashboard can move to `✅`.
