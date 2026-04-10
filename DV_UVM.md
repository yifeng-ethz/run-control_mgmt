# runctl_mgmt_host - UVM and Random Sweep Plan

**Parent:** [DV_PLAN.md](DV_PLAN.md)

This file defines the randomized layer for the standalone host verification.
The goal is not to model the whole SWB; it is to stress the local handshake
contracts and prove that the IP remains stable under interleaving and
backpressure.

## Proposed UVM Topology

| Agent | Role |
|------|------|
| `synclink_source` | drives run-control commands into `asi_synclink_data` |
| `upload_sink` | accepts or stalls `aso_upload_*` packets |
| `runctl_fanout_env` | models downstream ready behavior for `aso_runctl_*` |
| `mm_log_reader` | reads and flushes the log FIFO over the Avalon-MM port |

## Randomized Tests

| ID | Scenario | Randomized Dimensions |
|----|----------|-----------------------|
| U001 | Mixed command stream | command type, payload length, link gap, and reset injection |
| U002 | Run prepare / end stress | run number, upload stall window, and downstream ready delay |
| U003 | Run-control backpressure | number of consumers not ready, hold time, and release order |
| U004 | Log FIFO stress | MM read burst length, flush timing, and empty / non-empty transitions |
| U005 | Reset race | reset arrival relative to `POSTING` and `UPLOAD` states |
| U006 | Error recovery sweep | sync error injection, partial packet abort, and immediate retry |

## Randomization Goals

| Goal | Why |
|-----|-----|
| command coverage | every legal command is observed in a mixed stream |
| handshake coverage | upload and run-control backpressure are both exercised |
| recovery coverage | reset and error transitions return to idle without leakage |
| log coverage | FIFO readback and flush are exercised repeatedly |

## Planned Entry Point

The UVM layer should expose one regression entry and one smoke entry:

| Script | Purpose |
|-------|---------|
| `run_uvm.sh` | main randomized runner |
| `run_uvm_smoke.sh` | one-seed sanity run for local bring-up |

