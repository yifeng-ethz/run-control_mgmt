# RTL Plan: runctl_mgmt_host

## Scope

Standalone sign-off target for `rtl/runctl_mgmt_host.sv`, including the mixed-width logging FIFO wrapper and the exported `ext_hard_reset` conduit that mirrors RESET/STOP_RESET for other subsystems.

## Device And Clocks

- Device family: `Arria V`
- Device: `5AGXBA7D4F31C5`
- Nominal `lvdspll_clk`: `125 MHz`
- Nominal `mm_clk`: `150 MHz`
- Sign-off `lvdspll_clk`: `137.5 MHz` (`7.273 ns`, 1.1x nominal)
- Sign-off `mm_clk`: `165 MHz` (`6.061 ns`, 1.1x nominal)

## Architecture Model

- Receive / host / upload / CSR logic is expected to synthesize into ordinary ALM + FF control.
- The logging store should infer as one dual-clock mixed-width FIFO implemented in M10K RAM.
- The exported `ext_hard_reset` output is a single extra conduit on top of the existing dp/ct reset logic and should have negligible timing/resource impact.

## Resource Estimate

| Resource | Estimate | Rationale |
|----------|----------|-----------|
| ALMs | 900 | Control-heavy FSMs, CDC logic, CSR muxing, counters |
| Registers | 1100 | Snapshot banks, CDC synchronizers, counters, interface holding regs |
| Block memory bits | 32768 | 256 x 128b logging FIFO payload store |
| RAM blocks | 4 | Expected M10K usage for the logging FIFO |
| DSPs | 0 | No arithmetic blocks that should infer DSPs |

## Timing Risk Model

- `recv` to `host` handshake and CSR read muxing are the main expected combinational cones.
- The 48-bit gray/binary conversion and the 21-word CSR mux are the main mm-domain timing candidates.
- The logging FIFO should isolate most data-path storage cost into RAM, so the critical path should remain in control decode rather than payload storage.
