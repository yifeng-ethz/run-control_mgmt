# runctl_mgmt_host TB

This `tb/` tree is split into two layers:

- `sim/`: directed VHDL smoke benches for deterministic checks
- `uvm/`: SystemVerilog/UVM scaffolding for randomized stress

The verification target is the standalone `runctl_mgmt_host` IP, not the full
FEB or SWB system.

## Scope

The local testbench should prove:

1. synclink command decode
2. run-control fanout and handshake
3. upload acknowledgement emission
4. log FIFO readback through Avalon-MM
5. reset and recovery behavior

## Status

This tree is a scaffold. The first pass defines the directory split and the
planned test buckets, but it does not yet wire a full regression harness.

