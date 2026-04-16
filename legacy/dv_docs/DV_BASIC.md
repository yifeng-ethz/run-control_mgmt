# runctl_mgmt_host - Basic Directed Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)

These are the directed tests that should pass first. They are intentionally
small and deterministic so they can be used as smoke tests after RTL edits.

## Basic Cases

| ID | Scenario | What It Checks |
|----|----------|----------------|
| B001 | Reset defaults | All outputs, state, and timestamp counters come up clean after `lvdspll_reset` |
| B002 | `run_prepare` decode | Command `0x10` is accepted, payload length is 4 bytes, and the run number is captured correctly |
| B003 | `run_sync` decode | Command `0x11` maps to the expected `runctl` symbol and reaches all ready consumers |
| B004 | `start_run` fanout | Command `0x12` is accepted only after the downstream `ready` handshake completes |
| B005 | `end_run` upload | Command `0x13` produces the expected upload acknowledgement packet |
| B006 | `abort_run` decode | Command `0x14` maps to the safe fallback `runctl` symbol and does not emit an upload reply |
| B007 | Reset assert | Command `0x30` asserts the datapath and control reset outputs |
| B008 | Reset release | Command `0x31` deasserts the reset outputs and returns to idle cleanly |
| B009 | Enable / disable | Commands `0x32` and `0x33` do not deadlock the host and preserve log visibility |
| B010 | Address command | Command `0x40` consumes the 2-byte payload and terminates locally without waiting for downstream ack |
| B011 | Log FIFO sentence | A completed command appears as a 4-word sentence on the MM log interface |
| B012 | Readback ordering | The read side returns the log words in FIFO order with no reordering |
| B013 | Timestamp monotonicity | Repeated commands produce increasing receive and completion timestamps |
| B014 | Upload ready handshake | The upload packet is held until `aso_upload_ready` is asserted |
| B015 | No spurious traffic | Idle cycles do not produce run-control, upload, or MM log activity |

## Minimal Directed Harness

The directed layer should be split into a small number of standalone benches:

| Bench | Focus |
|------|-------|
| `smoke_reset_defaults` | power-up and hard reset state |
| `smoke_run_prepare_end` | prepare/end upload path and log record creation |
| `smoke_runctl_fanout` | run-control symbol decode and ready handshake |
| `smoke_log_fifo` | MM readback of the 4-word log sentence |

