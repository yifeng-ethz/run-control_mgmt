# runctl_mgmt_host UVM Scaffold

This directory will hold the randomized verification layer for
`runctl_mgmt_host`.

## Planned Components

| File | Role |
|------|------|
| `runctl_mgmt_host_pkg.sv` | transaction types, sequences, scoreboards, and coverage |
| `runctl_mgmt_host_tb_top.sv` | UVM top-level module |
| `run_uvm.sh` | regression entry point |

## Planned Agents

- synclink source agent
- upload sink agent
- run-control fanout environment
- Avalon-MM log reader

## Random Stress Focus

- command ordering under backpressure
- reset while a command is in flight
- repeated log read / flush cycles
- timestamp monotonicity across mixed traffic

