# runctl_mgmt_host Directed Simulation

This directory holds the deterministic VHDL smoke benches for
`runctl_mgmt_host`.

## Planned Benches

| Bench | Focus |
|------|-------|
| `tb_runctl_mgmt_host_directed.vhd` | combined smoke for decode, backpressure, upload ack, reset control, and log FIFO readback |

## Entry Point

- `run_questa_directed.sh` compiles the RTL plus the directed smoke bench and
  checks for the `RUNCTL_MGMT_HOST_DIRECTED_PASS` token.
- The directed harness uses `logging_fifo_sim.vhd` instead of the generated
  mixed-width FIFO primitive so the log path has a deterministic empty state in
  standalone simulation.

## Intended Checks

- decoded command symbol matches the RTL map
- upload ack appears only for `run_prepare` and `end_run`
- `aso_runctl_valid` stays asserted until the consumer is ready
- four MM reads reconstruct one full log sentence
- reset and stop-reset drive the hard-reset outputs deterministically
