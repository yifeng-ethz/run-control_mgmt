# runctl_mgmt_host - Design Verification Plan

**IP:** `runctl_mgmt_host`  
**Purpose:** receive run-control commands on `synclink`, fan them out on the
local `runctl` stream, emit upload acknowledgements, and expose the log FIFO on
`log` for JTAG master readback.

This plan is the entry point for standalone verification of the IP in
`mu3e_ip_dev`. It is intentionally small and focused on the behavior that
matters to the SWB and FEB integration:

1. decode and accept the supported run-control commands
2. forward the decoded run-control symbol to all downstream ready consumers
3. emit the expected upload reply for `run_prepare` and `run_end`
4. log the received timestamp and completion timestamp into the MM-visible FIFO
5. keep reset and error recovery deterministic

The RTL contract is defined by `runctl_mgmt_host.vhd` and the companion Qsys
wrapper `runctl_mgmt_host_hw.tcl`.

## Verification Model

| Layer | Purpose |
|------|---------|
| `tb/sim/` | directed VHDL smoke tests for decode, fanout, upload, and log readback |
| `tb/uvm/` | randomized SV/UVM sweeps for backpressure, reset, and interleaving stress |

## What Must Be Proven

| Area | Check |
|------|-------|
| Command decode | `run_prepare`, `run_sync`, `start_run`, `end_run`, `abort_run`, `reset`, `stop_reset`, `enable`, `disable`, `address` map to the expected local behavior |
| Run-control fanout | The decoded `runctl` symbol reaches every connected consumer and respects `ready` backpressure |
| Upload path | `run_prepare` and `end_run` produce a single upload packet with the expected symbol and payload |
| Log path | Each completed command generates a 4-word log sentence that can be drained over the MM slave |
| Reset recovery | Hard reset, soft reset, and link-error reset return the IP to a clean idle state |
| Timestamping | Received and completion timestamps remain monotonic across multiple commands |

## Document Split

| File | Scope |
|------|-------|
| `DV_BASIC.md` | directed bring-up and protocol correctness |
| `DV_EDGE.md` | boundary, backpressure, and recovery scenarios |
| `DV_UVM.md` | randomized and parameterized sweeps |

## Current Status

This is a scaffold. The first pass establishes the verification intent and the
directory split under `tb/`, but it does not yet add a full executable regression
environment.
