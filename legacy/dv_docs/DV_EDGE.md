# runctl_mgmt_host - Edge and Recovery Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)

This file covers the cases that are legal but sensitive: stalled handshakes,
link errors, reset races, and MM readback boundary conditions.

## Edge Cases

| ID | Scenario | What It Checks |
|----|----------|----------------|
| E001 | Synclink error at command start | Error bit `asi_synclink_error(2)` forces the host back to reset cleanly |
| E002 | Parity or decode error mid-payload | The receive state machine abandons the packet and does not emit a log sentence |
| E003 | Short payload | Fewer payload bytes than expected do not wedge the host |
| E004 | Long payload | Extra bytes after the expected payload are not mistaken for the next command |
| E005 | Upload backpressure | `aso_upload_valid` is held until the upload sink accepts the packet |
| E006 | Run-control backpressure | `aso_runctl_valid` remains asserted until all consumers are ready |
| E007 | MM read when FIFO empty | Readback returns the idle default and does not underflow |
| E008 | MM flush write | A non-all-ones write to the log MM interface clears the FIFO as intended |
| E009 | Reset during POSTING | A reset arriving while waiting for downstream ack returns to idle without a stale packet |
| E010 | Reset during UPLOAD | A reset arriving during upload arbitration does not duplicate the ack packet |
| E011 | Back-to-back run commands | Consecutive commands keep distinct timestamps and do not merge log entries |
| E012 | Address command boundary | `0x40` command terminates locally and does not consume extra idle bytes |
| E013 | Free-running timestamp wrap check | Timestamp progression is monotonic over multiple commands and is not reset by normal traffic |
| E014 | Empty FIFO after flush | A flush leaves the FIFO readable as empty to the JTAG master |

## Boundary Focus

The priority edge boundaries are:

| Boundary | Why It Matters |
|---------|----------------|
| `ready` held low | proves upload and run-control handshakes do not lose commands |
| link error asserted | proves the RX state machine does not retain partial packet state |
| FIFO empty / FIFO flushed | proves the log path is safe for the JTAG master |
| reset during active transaction | proves the host can recover without stale `done` state |

