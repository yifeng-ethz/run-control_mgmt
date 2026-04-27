## feb_system_v2 snapshot 2026-04-15

Reference baseline for the FEB SciFi `feb_system_v2` Platform Designer tree
that regenerates from a repository-local search path.

Source material:

- `online_dpv2/online/fe_board/fe_scifi/` at `b514aae93` for the authoring
  TCL and nested subsystem snapshots.
- `tmp/patch_fix_sc_burst_20260408/fe_scifi_stage/` for the last known-good
  generated Qsys shells that match the archived `feb_system_v2/synthesis`
  baseline.

### What is captured

| File                              | Role |
|-----------------------------------|------|
| `feb_system_v2.tcl`               | Authoritative top-level qsys-script TCL from the FE SciFi checkout |
| `feb_system_v2.qsys`              | Archived generated shell matching the old known-good baseline |
| `debug_sc_system_v2.tcl`          | Authoritative debug/control-path qsys-script TCL |
| `debug_sc_system_v2.qsys`         | XML generated from the TCL |
| `scifi_datapath_system_v2.qsys`   | Archived generated shell matching the old known-good baseline |
| `hit_stack_system.qsys`           | Archived generated shell matching the old known-good baseline |
| `mutrig_datapath_system_v2.qsys`  | Repo-local compatible nested MuTRiG datapath subsystem |
| `scifi_lvds_receiver_system.qsys` | Nested receiver dependency copied from `b514aae93` |
| `avst_errcnt_system.qsys`         | Nested error-counter dependency copied from `b514aae93` |
| `upload_system.qsys`              | Extra FE SciFi subsystem snapshot kept for reference |

### Why this snapshot exists

The current FE SciFi authoring tree is not fully self-contained inside this
repository. The archived `patch_fix_sc_burst_20260408` generation tree is the
last local baseline that regenerated cleanly and produced the checked-in
`feb_system_v2/synthesis` output. This snapshot keeps the minimum mix of Qsys
sources needed to reproduce that baseline shape with only:

```bash
export MU3E_IP_CORES_ROOT=/path/to/mu3e-ip-cores
qsys-generate run-control_mgmt/reference/feb_system_v2_snapshot_20260415/feb_system_v2.qsys \
  --search-path="$MU3E_IP_CORES_ROOT/firmware_builds,$" \
  --synthesis=VHDL
```

Validation on 2026-04-16:

- `qsys-generate` completes without errors from a clean parent checkout using
  only the repo-local search path above.
- The generated top-level `synthesis/feb_system_v2.vhd` matches the archived
  `tmp/patch_fix_sc_burst_20260408/fe_scifi_stage/feb_system_v2/synthesis`
  baseline byte-for-byte.
- Leaf generated files can still differ from the archived tree because the
  underlying IP repositories have moved forward since that baseline was first
  produced.

### How to compare later

```bash
diff -u tmp/patch_fix_sc_burst_20260408/fe_scifi_stage/feb_system_v2.qsys \
        run-control_mgmt/reference/feb_system_v2_snapshot_20260415/feb_system_v2.qsys
```
