# BUG_HISTORY.md - runctl_mgmt_host DV bug ledger

Class legend:
- `R` = RTL / DUT bug
- `H` = harness / testcase / reporting bug

Severity legend:
- `soft error` = the bad command retires incorrectly but later traffic can
  still recover without an explicit restart
- `hard stuck error` = the bug can wedge later command handling or keep a
  handshake busy until a downstream release or reset occurs
- `non-datapath-refactor` = observability, testcase, or documentation work with
  no direct command-path corruption

Encounterability legend:
- practical severity is `severity x encounterability`, so the index must say
  how likely a reader is to hit the bug in normal use rather than only when it
  first appeared in one simulation log
- nominal datapath operation = legal traffic, about `50%` link load, iid
  per-lane behavior, and no forced error injection or artificially pathological
  stalls
- nominal control-path operation = routine bring-up / CSR program / readback /
  clear-counter sequences
- `common (...)` = readily hit in nominal operation
- `occasional (...)` = hit in nominal operation without heroic setup, but not
  in every short run
- `rare (...)` = legal in nominal operation, but usually needs long runtime or
  unlucky alignment
- `corner-only (...)` = requires a legal but non-nominal stress or corner
  profile
- `directed-only (...)` = requires targeted error injection, formal/probe flow,
  reporting-only flow, or another non-operational stimulus
- detailed `min / p50 / max` first-hit sim-time studies may still appear
  inside individual bug sections

Fix status detail contract for active entries and future updates:
- `state` = fixed / open / partial plus the current verification gate
- `mechanism` = how the implemented repair changes the RTL or harness behavior
- `before_fix_outcome` and `after_fix_outcome` = concise evidence showing what
  changed
- `potential_hazard` = whether the fix looks permanent or still needs broader
  promotion into the planned matrix
- `Claude Opus 4.7 xhigh review decision` = explicit review state; use
  `pending / not run` until that review has actually happened

Historical formal note:
- this ledger starts on `2026-04-22` while the local IP worktree is rooted at
  `run-control_mgmt` commit `379e13a`
- the current supported simulator runtime is `QuestaOne 2026` at
  `/data1/questaone_sim/questasim`

## Index

| bug_id | class | severity | encounterability | status | first seen | commit | summary |
|---|---|---|---|---|---|---|---|
| [BUG-001-R](#bug-001-r-local_cmd-csr-stall-could-re-arm-the-same-avalon-write-beat-as-a-phantom-second-command) | R | hard stuck error | `directed-only (live FEB probe / directed standalone backpressure)` | fixed and rerun green in the local working tree | integrated FEB local-JTAG `LOCAL_CMD=0x31` probe on `2026-04-22` | `run-control_mgmt` base `379e13a` | `LOCAL_CMD` stall could re-arm one held Avalon write beat as a phantom second command and wedge `STATUS=0xC0010200` |
| [BUG-002-R](#bug-002-r-reset-and-stop-reset-could-deadlock-behind-downstream-run-control-fanout-ready) | R | hard stuck error | `occasional (control-path reset release)` | fixed and rerun green in the local working tree through targeted UVM and integrated RC TB | FEB run-control reset broadcast on `2026-04-24` | current working tree on `run-control_mgmt` base `379e13a` | `CMD_RESET` / `CMD_STOP_RESET` waited for downstream run-control fanout ready before releasing the reset tree |
| [BUG-003-R](#bug-003-r-synclink-run_prepare-decoded-swb-run-number-bytes-in-the-wrong-order) | R | soft error | `common (normal SWB RUN_PREPARE with non-palindromic run number)` | fixed and standalone-rerun green in the local working tree; integrated FEB rerun pending new image | FEB RC checker `run-prepare --run 42` on `2026-04-24` | current working tree on `run-control_mgmt` base `379e13a` | `RUN_NUMBER` CSR latched `0x2A000000` instead of `0x0000002A` because SWB sends run-number bytes least-significant first |
| [BUG-004-R](#bug-004-r-link-test-and-sync-test-reset-link-opcodes-were-dropped-as-unknown-by-the-feb-host) | R | soft error | `occasional (commissioning and diagnostic run-control command sweep)` | fixed and standalone-rerun green in the local working tree; regenerated-image rerun pending | FEB full RC checker `--sequence full` on `2026-04-25` | current working tree on `run-control_mgmt` base `379e13a` | `0x20`, `0x21`, `0x24`, `0x25`, and `0x26` echoed at the SWB reset-link status but were dropped by `runctl_mgmt_host` as unknown bytes |

## 2026-04-22

### BUG-001-R: `LOCAL_CMD` CSR stall could re-arm the same Avalon write beat as a phantom second command

- First seen in:
  - integrated FEB local-JTAG probe through
    `quartus_system/board_test/script/probe_runctl_local_host.tcl` with
    `--local-cmd 0x31 --post-delay-ms 100`
  - standalone direct reproducer
    `runctl_mgmt_host_local_cmd_backpressure_test`
  - nearest authored plan hooks:
    `DV_EDGE.md` `E097_local_cmd_busy_timing` and
    `E098_csr_waitrequest_release`
- Symptom:
  - integrated hardware and standalone sim both reached the same stuck status
    word: `STATUS=0xC0010200`
  - `LAST_CMD=0x00000000` and `RX_CMD_COUNT=0x00000000` did not advance
  - the host remained in `HOST_POSTING`, the receive side remained in
    `RECV_LOGGING`, and `STATUS.local_cmd_busy` stayed high
- Root cause:
  - while the CSR slave sat in `CSR_LOCAL_WAIT`, the Avalon master legally held
    the same `LOCAL_CMD` write beat active
  - when `local_cmd_busy_mm` cleared and the slave returned to `CSR_IDLE`,
    there was no one-beat holdoff to distinguish "same held transaction" from
    "new write request"
  - this allowed the same held Avalon beat to toggle `local_cmd_req_mm` a
    second time, creating a phantom follow-on local command behind the real
    in-flight command
  - if the first local command was already stalled on downstream
    `aso_runctl_ready`, the phantom second request kept the busy path live and
    recreated the same wedge seen in hardware
- Fix status:
  - state: fixed and standalone-rerun green in the current local working tree
  - mechanism:
    `rtl/runctl_mgmt_host.sv` now holds one `LOCAL_CMD` write beat in
    `local_cmd_req_hold_mm` / `local_cmd_hold_word_mm` so the CSR slave can arm
    each Avalon write beat only once until the master changes or releases it
  - before_fix_outcome:
    the new standalone direct reproducer failed with
    `local_cmd busy did not clear while host stalled in POSTING/LOGGING:
    status=0xc0010200`; the integrated FEB local-JTAG probe showed the same
    status word after a local `STOP_RESET`
  - after_fix_outcome:
    `runctl_mgmt_host_smoke_test`,
    `runctl_mgmt_host_synclink_cmd_matrix_test`, and
    `runctl_mgmt_host_local_cmd_backpressure_test` all pass in the current
    tree; the backpressure test ends with exactly one run-control beat and the
    log `Observed runctl=1 upload=0 reset_events=2`
  - potential_hazard:
    the broader planned bucket-library matrix is still not implemented; keep
    the direct backpressure test in the live regression set until the planned
    `E097` / `E098` coverage is promoted into the full authored matrix
  - Claude Opus 4.7 xhigh review decision:
    `pending / not run`
- Reproducer and evidence:
  - local IP git base:
    `run-control_mgmt` worktree rooted at commit `379e13a`
  - current standalone regression log:
    `logs/runctl_mgmt_host_local_cmd_backpressure_test.log`
  - current smoke logs:
    `logs/runctl_mgmt_host_smoke_test.log`,
    `logs/runctl_mgmt_host_synclink_cmd_matrix_test.log`
  - related authored plan sections:
    `DV_PLAN.md` section `6.2`,
    `DV_EDGE.md` `E013`, `E097`, and `E098`

## 2026-04-24

### BUG-002-R: reset and stop-reset could deadlock behind downstream run-control fanout ready

- First seen in:
  - FEB run-control broadcast reset debug on `2026-04-24`
  - SignalTap ready-chain capture
    `quartus_system/board_test/signaltap/phase4c_runctl_ready_reset_broadcast_high_20260424.vcd`
  - directed standalone and integrated regressions added/updated around
    reset/stop-reset fanout backpressure
- Symptom:
  - `runctl_mgmt_host_valid=1` while `runctl_mgmt_host_ready=0`
  - top fanout was blocked by downstream ready leaves, with observed stuck
    leaves including `out6=0` and `out14=0` at the hit-stack run-control
    consumers
  - a broadcast reset/stop-reset command could not complete if a downstream
    run-control slave was already not-ready due to the same reset tree the
    command needed to release
- Root cause:
  - `CMD_RESET` and `CMD_STOP_RESET` were included in
    `cmd_requires_fanout()`
  - the host therefore waited for the downstream `aso_runctl_ready`
    handshake before retiring these commands
  - the hard-reset conduits are driven from the host command-completion path,
    so a downstream fanout stall could prevent the reset release from ever
    reaching the blocked subsystem
- Fix status:
  - state:
    fixed and rerun green in the current local working tree through targeted
    UVM and the integrated RC TB
  - mechanism:
    `rtl/runctl_mgmt_host.sv` now treats `CMD_RESET` and `CMD_STOP_RESET` as
    hard-reset conduit commands that do not require downstream run-control
    fanout acknowledgement; normal run-control commands still require the
    fanout ready handshake
  - before_fix_outcome:
    hardware ready-chain capture showed the host stuck with valid high and
    ready low at the run-control fanout, blocked by hit-stack consumers
  - after_fix_outcome:
    `runctl_mgmt_host_smoke_test`,
    `runctl_mgmt_host_synclink_cmd_matrix_test`,
    `runctl_mgmt_host_local_cmd_backpressure_test`, and
    `runctl_mgmt_host_synclink_idle_guard_test` pass; after the top FEB
    run-control splitter was changed to a readyless broadcast, integrated
    `run_rc.sh` reaches all 16 datapath consumers without diagnostic ready
    forces and reaches both SWB link frame seams
  - potential_hazard:
    the upload subsystem still packages its CSR clock with the high-rate
    upload stream clock; splitting that into a pure 125 MHz control CSR clock
    is a separate future integration cleanup
  - Claude Opus 4.7 xhigh review decision:
    `pending / not run`
- Reproducer and evidence:
  - current standalone logs:
    `logs/runctl_mgmt_host_smoke_test.log`,
    `logs/runctl_mgmt_host_synclink_cmd_matrix_test.log`,
    `logs/runctl_mgmt_host_local_cmd_backpressure_test.log`,
    `logs/runctl_mgmt_host_synclink_idle_guard_test.log`
  - integrated regression:
    `quartus_system/tb_int/INT_fe_scifi_v3-2026-04-17/scripts/run_rc.sh`
  - related generated source:
    `quartus_system/feb_system_v3_pipe/synthesis/submodules/runctl_mgmt_host.sv`

### BUG-003-R: synclink `RUN_PREPARE` decoded SWB run-number bytes in the wrong order

- First seen in:
  - FEB hardware RC checker on `2026-04-24`:
    `python3 ./script/check_run_control.py --link 2 --sc-tool ./bin/sc_tool --rc-tool ./bin/rc_tool --device /dev/mudaq0`
  - `run-prepare --run 42` reached the FEB host, incremented
    `RX_CMD_COUNT`, and updated `LAST_CMD=0x10`, but latched
    `RUN_NUMBER=0x2A000000`
  - standalone reproducer:
    `runctl_mgmt_host_swb_run_number_endian_test`
- Symptom:
  - SWB status showed the run-prepare FSM advancing with
    `RESET_LINK_RUN_NUMBER_REGISTER_W=0x0000002A`
  - FEB CSR `RUN_NUMBER` read back `0x2A000000` instead of
    `0x0000002A`
  - reset, stop-reset, sync, start-run, and end-run all worked, so the
    failure was not a stuck run-control link or stuck fanout path
- Root cause:
  - SWB `a10_reset_link.vhd` sends `i_reset_run_number(7 downto 0)` first,
    followed by bytes `15:8`, `23:16`, and `31:24`
  - `runctl_mgmt_host.sv` shifted incoming payload bytes MSB-first, so the
    first byte became `RUN_NUMBER[31:24]`
- Fix status:
  - state:
    fixed and standalone-rerun green in the current local working tree;
    integrated FEB hardware rerun pending a regenerated Qsys image and full
    Quartus rebuild
  - mechanism:
    `rtl/runctl_mgmt_host.sv` now records synclink payload bytes into
    `payload32` by byte lane and latches `RUN_PREPARE` in SWB reset-link
    order, while preserving the CSR `LOCAL_CMD` run-number packing contract
  - before_fix_outcome:
    `runctl_mgmt_host_swb_run_number_endian_test_before_fix.log` failed with
    `Timed out waiting for RUN_NUMBER=0x0000002a`
  - after_fix_outcome:
    `runctl_mgmt_host_swb_run_number_endian_test` passes and the broader
    standalone command/reset regressions are rerun as part of the current
    FEB bring-up loop
  - potential_hazard:
    `CMD_ADDRESS` remains a local extension with high-byte-first payload
    interpretation in the current tests; only the SWB `RUN_PREPARE` run-number
    contract is changed by this fix
  - Claude Opus 4.7 xhigh review decision:
    `pending / not run`
- Reproducer and evidence:
  - before-fix standalone log:
    `logs/runctl_mgmt_host_swb_run_number_endian_test_before_fix.log`
  - after-fix standalone log:
    `logs/runctl_mgmt_host_swb_run_number_endian_test.log`
  - live hardware evidence:
    `quartus_system/board_test/reports/check_run_control_20260424_pipe.log`

## 2026-04-25

### BUG-004-R: link-test and sync-test reset-link opcodes were dropped as unknown by the FEB host

- First seen in:
  - FEB hardware full RC checker:
    `quartus_system/board_test/reports/check_run_control_full_20260425_runctl264_seed3.log`
  - failing opcodes:
    `start-link-test` (`0x20`), `stop-link-test` (`0x21`),
    `start-sync-test` (`0x24`), `test-sync` (`0x26`), and
    `stop-sync-test` (`0x25`)
- Symptom:
  - SWB `RESET_LINK_STATUS_REGISTER_R` echoed each opcode in its top byte,
    proving the reset-link transmitter accepted and emitted the command
  - FEB `runctl_mgmt_host` did not increment `RX_CMD_COUNT`
  - FEB `LAST_CMD` remained at the previous accepted opcode (`0x14` in the
    failing sweep)
  - normal run, reset, enable, and disable opcodes still worked, so the failure
    was command coverage in the host decoder rather than a stuck SC hub,
    Merlin interconnect, LVDS controller, or run-control fanout
- Root cause:
  - `runctl_mgmt_host.sv` did not define the reset-protocol diagnostic opcodes
    `0x20`, `0x21`, `0x24`, `0x25`, or `0x26`
  - `cmd_is_known()` therefore classified those legal reset-link bytes as
    unknown commands and returned to `RECV_CLEANUP` without logging,
    incrementing `RX_CMD_COUNT`, or fanning out a run-control state
- Fix status:
  - state:
    fixed and standalone-rerun green in the local working tree;
    regenerated-image hardware rerun pending
  - mechanism:
    `rtl/runctl_mgmt_host.sv` now treats the link-test and sync-test opcodes
    as zero-payload legal commands and maps them to `LINK_TEST`,
    `SYNC_TEST`, or `IDLE` one-hot run-control states
  - before_fix_outcome:
    `check_run_control.py --sequence full` reported `SUMMARY pass=11 fail=5`
    with all five failures in the diagnostic link/sync-test opcode group
  - after_fix_outcome:
    `runctl_mgmt_host_synclink_cmd_matrix_test` passes with
    `Observed runctl=12 upload=2 reset_events=2`; the smoke, SWB run-number
    endian, and local-command backpressure tests also pass after the decoder
    change. Qsys regeneration, Quartus rebuild, and hardware full RC rerun are
    still pending.
  - potential_hazard:
    the online reset-protocol header marks some diagnostic commands as
    payload-capable; the current SWB-side `rc_tool` emits them as single-byte
    commands, matching the observed hardware path tested here
  - Claude Opus 4.7 xhigh review decision:
    `pending / not run`
- Reproducer and evidence:
  - live hardware pre-fix log:
    `quartus_system/board_test/reports/check_run_control_full_20260425_runctl264_seed3.log`
  - targeted standalone test extended in:
    `runctl_mgmt_host_synclink_cmd_matrix_test`
