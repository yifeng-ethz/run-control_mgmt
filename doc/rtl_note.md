# rtl_note: runctl_mgmt_host

## Targets

- Device: `Arria V / 5AGXBA7D4F31C5`
- Nominal clocks: `lvdspll_clk=125 MHz`, `mm_clk=150 MHz`
- Standalone sign-off clocks: `lvdspll_clk=137.5 MHz`, `mm_clk=165 MHz`
- Timing gate from `doc/RTL_PLAN.md`: compile the standalone Quartus harness at the tightened 1.1x clocks and require `WNS >= 0` plus `hold slack >= 0` on the selected sign-off clocks.

## Pre-fit Model

- One dual-clock mixed-width FIFO should dominate RAM usage.
- Receive / host / upload / CSR / CDC logic should dominate ALMs and FFs.
- `ext_hard_reset` is only an extra exported conduit on top of the existing reset logic and should have negligible timing and area impact.

Observed implementation matches the model: the fitter uses `4` RAM blocks / `32768` block memory bits for the logging FIFO, while the critical setup path remains in the `mm_clk` control / CSR side rather than in payload storage.

## DV Evidence

- RTL smoke: `make -C tb run_uvm_smoke`
  - log: `tb/logs/runctl_mgmt_host_smoke_test.log`
  - result: pass
  - scoreboard: `Observed runctl=6 upload=2 reset_events=3`
- Gate smoke: `make -C tb run_gate_uvm_smoke`
  - log: `tb/logs/runctl_mgmt_host_smoke_test_gate.log`
  - result: pass
  - scoreboard: `Observed runctl=6 upload=2 reset_events=3`

The gate runner uses the Quartus-generated post-fit netlist from `syn/quartus/gate_sim/runctl_mgmt_host_syn.vo` through `tb/sim/runctl_mgmt_host_gate_dut_wrapper.sv`. On this Arria V flow, `quartus_eda` emits a post-fit functional Verilog netlist only; SDF timing back-annotation is not available here, so the gate evidence is functional post-fit smoke rather than timed SDF simulation.

`tb/DV_PLAN.md` is still a larger planned catalog. This note therefore records smoke-level RTL + post-fit gate evidence for the upgrade, not full catalog closure of every planned DV item.

## Lint Evidence

Command:

- `./lint/run_lint.sh`

Generated summary (`lint/summary.md`, 2026-04-13 13:08:32 +02:00):

- Layer 1 source: `0` errors / `0` warnings
- Layer 2 elab: `0` errors / `0` warnings
- Layer 3a syn DA: `0` errors / `7` warnings
- Layer 3b fit DA: `0` errors / `6` warnings
- Layer 3c sta CDC: `0` errors / `0` warnings
- Layer 3d design assistant: `0` errors / `31` warnings

Remaining lint caveats:

- One real HDL warning remains in synthesis: `runctl_mgmt_host.sv(773)` reports `log_drop_gray_ff1` assigned but never read.
- The standalone lint harness has intentionally incomplete pin assignments, so Quartus fit reports the expected `Some pins have incomplete I/O assignments`, `No exact pin location assignment(s)`, and shared-VREF GPIO warnings.
- Design Assistant raises `Critical Warning (308060)` / rule `D101` for `185` asynchronous interface structures rooted at the multi-bit status snapshot bus around `runctl_mgmt_host.sv:703`. This is expected for the intentional snapshot-style CDC scheme and is the main reason the DA warning count stays nonzero.

## Timing And Resources

Command:

- `syn/quartus/run_signoff.sh`

Constraint packaging used for this sign-off:

- The CDC intent is now packaged in `runctl_mgmt_host.sdc` and sourced through `runctl_mgmt_host_hw.tcl`, so Platform Designer integrations inherit the same per-IP timing exceptions.
- The standalone harness keeps only the clock definitions in `syn/quartus/runctl_mgmt_host_syn.sdc`; the previous blanket `set_clock_groups -asynchronous` cut between `mm_clk` and `lvdspll_clk` is no longer used.

Timing summary from `syn/quartus/output_files/runctl_mgmt_host_syn.sta.summary`:

- Worst setup slack across the selected sign-off clocks/corners: `0.488 ns`
  - corner: `Slow 1100mV 85C`
  - clock: `mm_clk`
- Worst hold slack across the selected sign-off clocks/corners: `0.146 ns`
  - corner: `Fast 1100mV 0C`
  - clock: `lvdspll_clk`
- All reported setup / hold `TNS` values for `mm_clk` and `lvdspll_clk` are `0.000`.

Spot-checking the saved post-fit timing paths after this change shows the worst remaining setup path is same-domain `mm_clk` CSR logic (`gts_gray_mm_ff1[*] -> avs_csr_readdata[*]`). The previous `lvdspll_clk -> mm_clk` snapshot / status CDC paths are no longer present in the critical path list.

This satisfies the `doc/RTL_PLAN.md` timing gate because the standalone build was constrained at the tightened `137.5 / 165 MHz` sign-off clocks and both setup and hold slacks remain non-negative.

Resource summary from `syn/quartus/output_files/runctl_mgmt_host_syn.fit.summary`:

| Resource | Estimate | Actual | Ratio | Status |
|----------|----------|--------|-------|--------|
| ALMs | 900 | 759 | 0.84x | pass |
| Registers | 1100 | 1592 | 1.45x | pass |
| Block memory bits | 32768 | 32768 | 1.00x | pass |
| RAM blocks | 4 | 4 | 1.00x | pass |
| DSPs | 0 | 0 | 1.00x | pass |

All measured resources stay within the required `0.5x` to `3.0x` envelope from `doc/RTL_PLAN.md`.

## Plan Mapping

- `doc/RTL_PLAN.md`
  - device and clock targets match
  - expected FIFO-in-M10K mapping observed
  - resource envelope satisfied
  - timing closed at the tightened standalone sign-off clocks
- `tb/DV_PLAN.md`
  - implemented smoke path passes in both RTL and post-fit gate modes
  - broader planned catalog is not yet fully automated or closed

## Upgrade Sign-off Status

The `26.1.0.413` run-control management host packaging is signed off for this upgrade scope on timing, resource usage, lint review, RTL smoke, and post-fit functional gate smoke. The remaining known caveats are the expected standalone-harness lint noise, the intentional Design Assistant CDC false positives on the snapshot bus, and the fact that the full `tb/DV_PLAN.md` catalog is still broader than the currently implemented smoke regression.
