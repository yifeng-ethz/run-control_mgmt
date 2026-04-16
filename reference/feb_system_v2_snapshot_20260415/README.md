## feb_system_v2 snapshot 2026-04-15

Reference snapshot of the FEB SciFi `feb_system_v2` Qsys tree *before*
wiring runctl_mgmt_host `ext_hard_reset` / `dp_hard_reset` / `ct_hard_reset`
into the subsystem reset fanout.

Source checkout: `online_dpv2/online/fe_board/fe_scifi/` at
`b514aae93` (FEB SciFi round-5 Option-C ship build).

### What is captured

| File                              | Authoring form |
|-----------------------------------|----------------|
| `feb_system_v2.tcl`               | qsys-script TCL (authoritative source) |
| `feb_system_v2.qsys`              | XML generated from the TCL via `save_system` |
| `debug_sc_system_v2.tcl`          | qsys-script TCL (authoritative source) |
| `debug_sc_system_v2.qsys`         | XML generated from the TCL |
| `scifi_datapath_system_v2.qsys`   | XML-authored (no .tcl source in tree) |
| `upload_system.qsys`              | XML-authored (no .tcl source in tree) |
| `mutrig_datapath_system_v2.qsys`  | XML-authored (no .tcl source in tree) |
| `scifi_lvds_receiver_system.qsys` | XML-authored snapshot dependency |
| `hit_stack_system.qsys`           | XML-authored snapshot dependency |
| `avst_errcnt_system.qsys`         | XML-authored snapshot dependency |

### Why this snapshot exists

The current wiring of `feb_system_v2.qsys` has `runctl_mgmt_host_0`
`ct_hard_reset`, `dp_hard_reset`, and `ext_hard_reset` reset-source
conduits exported out of `upload_subsystem` but **dangling** at the
top level. Result: `CMD_RESET` (0x30) and `CMD_STOP_RESET` (0x31)
from the SWB run-control link do not reach `control_path_subsystem`
or `data_path_subsystem` — the `sc_hub_core` drop counters, the
legacy `max10_prog_avmm` CSR state, the `onewire_master_controller`,
the `firefly_xcvr_ctrl`, the `on_die_temp_sense`, the `mm_bridge`,
the datapath counters, etc. all stay at whatever value they held
when the command was issued. The top-level `reset` conduit (hooked
to `mclk125_souce.clk_in_reset` and cascaded into
`cclk156_source.clk_in_reset`) is only exercised on external
power-up reset; the runctl RESET command has no hook into it.

This snapshot preserves the pre-modification system so the new
reset-fanout wiring (pipelined, CDC-synchronized from the
`lvdspll_clk` source domain into the `cclk156` and `mclk125`
destination domains) can be compared against the baseline.

The three nested subsystem `.qsys` files are copied from the same
`b514aae93` FE SciFi snapshot so `qsys-generate` can resolve the
captured tree using only repository-local search paths.

### Intended follow-up changes (not applied yet)

1. Connect `upload_subsystem.ext_hard_reset_out` (once exported at
   the subsystem boundary) to a new `altera_reset_bridge` chain in
   `feb_system_v2` that:
   - synchronizes from `lvdspll_clk` → `cclk156` (and `mclk125`
     where needed)
   - pipelines the synchronized reset across 2–3 flop stages to
     absorb the fanout without regressing the round-5 timing
     margin
   - OR-merges with the existing `cclk156_source.clk_reset`
     (or feeds a new dedicated `hard_reset` sink on each
     subsystem) so that `control_path_subsystem`,
     `data_path_subsystem`, and the non-`runctl_mgmt_host`
     portions of `upload_subsystem` all observe the RESET pulse.
2. Verify each IP inside the three subsystems actually
   responds to its `csr_reset` / `avmm_rst` / `clk156_in_rst`
   input — registers, counters, and FSMs should return to
   power-up state; M10K / LUTRAM storage is not required to
   clear (consistent with a cold hard reset).
3. Do **not** loop `ext_hard_reset` back into
   `runctl_mgmt_host_0.lvdspll_reset` or `.mm_reset` — the IP's
   own header explicitly warns this creates a latch-up.

### How to compare later

```
diff -u feb_system_v2_snapshot_20260415/feb_system_v2.tcl \
        online_dpv2/online/fe_board/fe_scifi/feb_system_v2.tcl
```
