# ⚠️ SYN Report — runctl_mgmt_host

**Revision:** `runctl_mgmt_host_syn` &nbsp; **Date:** `2026-04-22` &nbsp;
**Device:** `5AGXBA7D4F31C5` &nbsp; **Quartus:** `18.1.0 Build 625` &nbsp;
**Evidence basis:** standalone Quartus output from `2026-04-16` plus the
`2026-04-22` standalone QuestaOne reruns for `BUG-001-R`

This file is the detailed standalone synthesis and timing note for
`runctl_mgmt_host`. The master signoff dashboard is
[`../doc/SIGNOFF.md`](../doc/SIGNOFF.md).

## Build Intent

- compile the standalone Arria V harness under `syn/quartus/`
- constrain `mm_clk` and `lvdspll_clk` at the tightened standalone signoff
  clocks from `doc/rtl_note.md`
- keep timing and resource signoff separate from the broader FEB integration
- record the functional caveat that surfaced after the last standalone Quartus
  rerun:
  [`BUG-001-R`](../tb/BUG_HISTORY.md#bug-001-r-local_cmd-csr-stall-could-re-arm-the-same-avalon-write-beat-as-a-phantom-second-command)

## Functional Fix Linked To This Synthesis Point

- canonical standalone reproducer:
  `runctl_mgmt_host_local_cmd_backpressure_test`
- canonical live-hardware reproducer:
  local-JTAG `LOCAL_CMD=0x31` through
  `firmware_builds/board_test/script/probe_runctl_local_host.tcl`
- bug summary:
  one held `LOCAL_CMD` Avalon write beat could be re-armed as a phantom second
  command while the first command was still stalled on `aso_runctl_ready`
- current status:
  the RTL fix is in the local working tree and the standalone QuestaOne reruns
  are green; the standalone Quartus `runctl_mgmt_host_syn` compile has not yet
  been rerun after this fix, so the timing/resource numbers below are still the
  last measured standalone fit from `2026-04-16`

## Timing Summary

Signoff targets from `doc/rtl_note.md`:

- `mm_clk = 165 MHz`
- `lvdspll_clk = 137.5 MHz`

Measured summary from `syn/quartus/output_files/runctl_mgmt_host_syn.sta.summary`:

| status | model | `mm_clk` setup WNS (ns) | `lvdspll_clk` setup WNS (ns) | worst hold WNS (ns) |
|:---:|---|---:|---:|---:|
| ✅ | Slow `1100mV 85C` | `+0.597` | `+1.944` | `+0.272` |
| ✅ | Slow `1100mV 0C`  | `+0.759` | `+2.249` | `+0.236` |
| ✅ | Fast `1100mV 85C` | `+2.878` | `+3.974` | `+0.164` |
| ✅ | Fast `1100mV 0C`  | `+3.166` | `+4.344` | `+0.129` |

Key conclusions:

- the measured standalone `runctl_mgmt_host_syn` compile closes setup and hold
  on both signoff clocks across the reported corners
- the worst measured setup path is still in the `mm_clk` control / CSR cone,
  not the `lvdspll_clk` fanout path
- `BUG-001-R` is a functional CSR / waitrequest sequencing defect and does not
  by itself invalidate the measured timing or resource data from the last clean
  standalone fit

## Resource Summary

Measured summary from `syn/quartus/output_files/runctl_mgmt_host_syn.fit.summary`:

| item | value |
|---|---|
| Logic utilization | `761 / 91,680 ALMs (<1%)` |
| Registers | `1,599` |
| Pins | `142 / 426 (33%)` |
| Block memory bits | `32,768 / 13,987,840 (<1%)` |
| RAM blocks | `4 / 1,366 (<1%)` |
| DSP blocks | `0 / 800` |
| PLLs | `0 / 21` |

The storage model is still dominated by the logging FIFO, which maps to `4`
RAM blocks and `32,768` block-memory bits.

## Functional Evidence Paired With This Report

- [`../tb/BUG_HISTORY.md`](../tb/BUG_HISTORY.md)
- [`../tb/logs/runctl_mgmt_host_smoke_test.log`](../tb/logs/runctl_mgmt_host_smoke_test.log)
- [`../tb/logs/runctl_mgmt_host_synclink_cmd_matrix_test.log`](../tb/logs/runctl_mgmt_host_synclink_cmd_matrix_test.log)
- [`../tb/logs/runctl_mgmt_host_local_cmd_backpressure_test.log`](../tb/logs/runctl_mgmt_host_local_cmd_backpressure_test.log)

Current standalone direct-test results:

| test | result | note |
|---|---|---|
| `runctl_mgmt_host_smoke_test` | pass | scoreboard `runctl=3 upload=1 reset_events=3` |
| `runctl_mgmt_host_synclink_cmd_matrix_test` | pass | scoreboard `runctl=9 upload=2 reset_events=2` |
| `runctl_mgmt_host_local_cmd_backpressure_test` | pass | canonical regression for `BUG-001-R` |

## Artifacts

- [`quartus/runctl_mgmt_host_syn.qsf`](quartus/runctl_mgmt_host_syn.qsf)
- [`quartus/runctl_mgmt_host_syn.sdc`](quartus/runctl_mgmt_host_syn.sdc)
- [`quartus/runctl_mgmt_host_syn_top.sv`](quartus/runctl_mgmt_host_syn_top.sv)
- [`quartus/output_files/runctl_mgmt_host_syn.fit.summary`](quartus/output_files/runctl_mgmt_host_syn.fit.summary)
- [`quartus/output_files/runctl_mgmt_host_syn.sta.summary`](quartus/output_files/runctl_mgmt_host_syn.sta.summary)
- [`quartus/output_files/runctl_mgmt_host_syn.fit.rpt`](quartus/output_files/runctl_mgmt_host_syn.fit.rpt)
- [`quartus/output_files/runctl_mgmt_host_syn.sta.rpt`](quartus/output_files/runctl_mgmt_host_syn.sta.rpt)

## Result

**⚠️ Partial standalone signoff**

The last measured standalone Quartus compile remains timing-clean and
resource-clean, and the `2026-04-22` standalone functional reruns close the
`BUG-001-R` local-command backpressure defect. A post-fix standalone Quartus
rerun is still pending before this can be promoted to a fully refreshed
standalone signoff point for the fixed RTL image.
