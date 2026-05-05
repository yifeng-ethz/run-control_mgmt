# DV Plan: runctl_mgmt_host (SystemVerilog rewrite)

**DUT:** `runctl_mgmt_host`
**IP source:** `rtl/runctl_mgmt_host.sv`
**Legacy reference:** `legacy/runctl_mgmt_host_v24.vhd` (semantics frozen for synclink/runctl/upload datapath)
**Author:** Yifeng Wang (yifenwan@phys.ethz.ch)
**Date:** 2026-04-13
**Status:** Active plan with an implemented standalone smoke harness. The
QuestaOne 2026 `run_uvm_smoke` rerun passes on this host; broader bucketed
coverage in this document remains planned until promoted into refreshed live
reports. This document is the canonical catalog and supersedes
`legacy/dv_docs/DV_PLAN.md`.

---

## 1. Purpose & Scope

`runctl_mgmt_host` is the on-FPGA receiver and dispatcher between the Mu3e central run-control box and the local run-control fabric. This plan covers standalone DV of the rewritten SystemVerilog implementation, including the expanded CSR block.

### In-scope

- `synclink_recv` FSM: byte-level command parsing, payload assembly, error counters, snapshot capture
- `runctl_host` FSM: decoded command fanout on readyless `runctl` AVST source
- `rc_pkt_upload` FSM: 36-bit upload AVST source for RC ack packets (RUN_PREPARE / END_RUN)
- `local_cmd` injection path with toggle-handshake CDC from mm_clk to lvdspll_clk
- 5-bit / 32-bit AVMM CSR slave on `mm_clk` (word-addressed)
- Logging dual-clock FIFO (Altera `dcfifo_mixed_widths`, 128-bit write × 32-bit read) and sub-word readback through `LOG_POP`
- `dp_hard_reset` / `ct_hard_reset` synchronous outputs in lvdspll_clk domain with per-domain mask from CONTROL CSR
- All cross-domain paths (status snapshot toggle, gray-coded gts CDC, free-running counter CDC, atomic GTS_L/GTS_H snapshot)

### Out-of-scope

- Central run-control box and 5G link encoder/decoder. Stimulus is injected directly as 9-bit synclink bytes; no link-layer codec is modeled.
- Real downstream run-control agents. The runctl AVST source is observed as a readyless broadcast stream.
- Quartus place-and-route timing closure.
- Bitstream-level register access from JTAG-Avalon master (pure Avalon-MM functional model only).

---

## 2. DUT Interfaces

| Interface | Type | Width | Clock | Direction | Notes |
|-----------|------|-------|-------|-----------|-------|
| `synclink` | AVST sink | data 9b (k+8b), error 3b | `lvdspll_clk` | in | data[8]=k-flag; error[2]=loss_sync, [1]=parity, [0]=decode |
| `runctl` | AVST source | 9b | `lvdspll_clk` | out | decoded run-control fanout, readyless one-cycle valid broadcast |
| `upload` | AVST source | 36b | `lvdspll_clk` | out | RC ack packets (sop/eop), data[35:32] are k-flags |
| `csr` | AVMM slave | addr 5b (word), data 32b | `mm_clk` | in/out | 1-cycle read latency, no waitrequest |
| `dp_hard_reset` | conduit | 1b | `lvdspll_clk` | out | sync to lvdspll, masked by CONTROL.rst_mask_dp |
| `ct_hard_reset` | conduit | 1b | `lvdspll_clk` | out | sync to lvdspll, masked by CONTROL.rst_mask_ct |
| `mm_clk` / `mm_reset` | clock/reset | 1b | self | in | arbitrary frequency 100–200 MHz |
| `lvdspll_clk` / `lvdspll_reset` | clock/reset | 1b | self | in | 125 MHz datapath clock, asynchronous to mm_clk |

---

## 3. CSR Register Map

5-bit word address, 32-bit data. All accesses are word-aligned. Read latency = 1 mm_clk cycle.

| Word | Name         | Access | Fields |
|------|--------------|--------|--------|
| 0x00 | UID          | RO     | 32-bit ASCII `RCMH` = 0x52434D48 (HDL parameter override at integration) |
| 0x01 | META         | RW/RO  | Write [1:0]=page selector; read returns: 0=VERSION, 1=DATE, 2=GIT, 3=INSTANCE_ID |
| 0x02 | CONTROL      | RW     | [0] soft_reset (W1P), [1] log_flush (W1P), [4] rst_mask_dp, [5] rst_mask_ct |
| 0x03 | STATUS       | RO     | [0] recv_idle, [1] host_idle, [4] dp_hard_reset, [5] ct_hard_reset, [15:8] recv_state_enc, [23:16] host_state_enc, [30] local_cmd_busy, [31] log_fifo_empty |
| 0x04 | LAST_CMD     | RO     | [7:0] last run_command, [31:16] last fpga_address snapshot |
| 0x05 | SCRATCH      | RW     | 32-bit general-purpose scratch |
| 0x06 | RUN_NUMBER   | RO     | 32-bit last run_number from RUN_PREPARE |
| 0x07 | RESET_MASK   | RO     | [15:0] last reset_assert_mask, [31:16] last reset_release_mask |
| 0x08 | FPGA_ADDRESS | RO     | [15:0] last CMD_ADDRESS payload, [31] valid-sticky |
| 0x09 | RECV_TS_L    | RO     | recv_ts[31:0] of most recent command |
| 0x0A | RECV_TS_H    | RO     | recv_ts[47:32] |
| 0x0B | EXEC_TS_L    | RO     | exec_ts[31:0] of most recent command |
| 0x0C | EXEC_TS_H    | RO     | exec_ts[47:32] |
| 0x0D | GTS_L        | RO     | live gts_counter[31:0]; reading latches [47:32] into GTS_H (atomic snapshot) |
| 0x0E | GTS_H        | RO     | latched gts_counter[47:32] from the last GTS_L read |
| 0x0F | RX_CMD_COUNT | RO     | accepted command count, saturating |
| 0x10 | RX_ERR_COUNT | RO     | synclink parity/decode/loss-sync error count, saturating |
| 0x11 | LOG_STATUS   | RO     | [9:0] rdusedw, [16] rdempty, [17] rdfull |
| 0x12 | LOG_POP      | RO     | read auto-pops one 32-bit log sub-word; reads on empty return 0 |
| 0x13 | LOCAL_CMD    | RW     | write submits one 32-bit local command word; blocked by STATUS.local_cmd_busy. Read returns last submitted word |
| 0x14 | ACK_SYMBOLS  | RO     | [7:0] RUN_START_ACK_SYMBOL parameter (default 0xFE), [15:8] RUN_END_ACK_SYMBOL parameter (default 0xFD) |

### 3.1 CONTROL field breakdown

| Bit | Name | Type | Meaning |
|-----|------|------|---------|
| 0   | soft_reset    | W1P | Pulse: clears recv FSM, host FSM, snapshot record, log FIFO read pointer |
| 1   | log_flush     | W1P | Pulse: drains the log FIFO (read side) until empty |
| 4   | rst_mask_dp   | RW  | 1 = suppress `dp_hard_reset` assertion on CMD_RESET / CMD_STOP_RESET |
| 5   | rst_mask_ct   | RW  | 1 = suppress `ct_hard_reset` assertion on CMD_RESET / CMD_STOP_RESET |
| others | reserved   | RO  | read as 0, write ignored |

### 3.2 STATUS field breakdown

| Bit(s) | Name | Meaning |
|--------|------|---------|
| 0      | recv_idle        | synclink_recv FSM in IDLE |
| 1      | host_idle        | runctl_host FSM in IDLE |
| 4      | dp_hard_reset    | live dp_hard_reset output (post-mask, sampled in lvdspll, CDC'd) |
| 5      | ct_hard_reset    | live ct_hard_reset output |
| 15:8   | recv_state_enc   | encoded synclink_recv FSM state |
| 23:16  | host_state_enc   | encoded runctl_host FSM state |
| 30     | local_cmd_busy   | local_cmd toggle handshake in flight |
| 31     | log_fifo_empty   | log FIFO read side empty |

### 3.3 META page mux

| Page (W[1:0]) | Read return |
|---------------|-------------|
| 0 | VERSION: [31:24]=MAJOR, [23:16]=MINOR, [15:12]=PATCH, [11:0]=BUILD |
| 1 | DATE: YYYYMMDD packed BCD or hex (per integration) |
| 2 | GIT: truncated 32-bit git short hash |
| 3 | INSTANCE_ID: HDL parameter |

### 3.4 LAST_CMD field breakdown

| Bits | Field | Source |
|------|-------|--------|
| 7:0   | last_run_command  | last latched command byte (any of 0x10–0x14 / 0x30–0x33 / 0x40) |
| 15:8  | reserved          | RO 0 |
| 31:16 | last_fpga_address | last CMD_ADDRESS payload (mirror of FPGA_ADDRESS[15:0]) |

### 3.5 RESET_MASK field breakdown

| Bits | Field | Source |
|------|-------|--------|
| 15:0  | last_reset_assert_mask  | last CMD_RESET (0x30): 0xFFFF for synclink broadcast, or CSR_LOCAL_CMD [23:8] for local_cmd path |
| 31:16 | last_reset_release_mask | last CMD_STOP_RESET (0x31): 0xFFFF for synclink broadcast, or CSR_LOCAL_CMD [23:8] for local_cmd path |

### 3.6 Log entry layout (4 sub-words per command, popped via LOG_POP)

| Sub-word | Bits | Content |
|----------|------|---------|
| 0 | 31:0  | recv_ts[47:16] |
| 1 | 31:16 | recv_ts[15:0] |
| 1 | 15:8  | reserved (0) |
| 1 | 7:0   | run_command[7:0] |
| 2 | 31:0  | payload[31:0] (run_number for RUN_PREPARE; {assert, release} for RESET; address for ADDRESS; 0 otherwise) |
| 3 | 31:0  | exec_ts[31:0] |

### 3.7 Command byte encoding (synclink + local_cmd)

| Code | Name | Payload | Notes |
|------|------|---------|-------|
| 0x10 | RUN_PREPARE   | 32b run number | Generates upload ack with K30.7 (0xFE) |
| 0x11 | RUN_SYNC      | none | Fanout only |
| 0x12 | START_RUN     | none | Fanout only |
| 0x13 | END_RUN       | none | Generates upload ack with K29.7 (0xFD) |
| 0x14 | ABORT_RUN     | none | Fanout only |
| 0x20 | START_LINK_TEST | none | Fanout LINK_TEST |
| 0x21 | STOP_LINK_TEST | none | Fanout IDLE |
| 0x24 | START_SYNC_TEST | none | Fanout SYNC_TEST |
| 0x25 | STOP_SYNC_TEST | none | Fanout IDLE |
| 0x26 | TEST_SYNC     | none | Fanout SYNC_TEST pulse/state |
| 0x30 | RESET         | **synclink: none** (broadcast, spec-aligned with Mu3e SpecBook §4.6.2); `local_cmd`: optional 16b assert mask in the upper 24b of CSR_LOCAL_CMD | Pulses exported `ext_hard_reset` for `EXT_HARD_RESET_PULSE_CYCLES`; drives local `dp_hard_reset` / `ct_hard_reset` subject to the CONTROL mask bits. Synclink path latches `assert_mask = 0xFFFF` (all channels). |
| 0x31 | STOP_RESET    | **synclink: none** (broadcast, spec-aligned with Mu3e SpecBook §4.6.2); `local_cmd`: optional 16b release mask in the upper 24b of CSR_LOCAL_CMD | Cancels any active `ext_hard_reset` pulse; releases local `dp_hard_reset` / `ct_hard_reset` subject to the CONTROL mask bits. Synclink path latches `release_mask = 0xFFFF`. |
| 0x32 | ENABLE        | none | Fanout only |
| 0x33 | DISABLE       | none | Fanout only |
| 0x40 | ADDRESS       | 16b fpga address | Latches CSR.FPGA_ADDRESS only; does NOT fan out on runctl |

---

## 4. Test Bucket Overview

| File | Prefix | Range | Rationale |
|------|--------|-------|-----------|
| `DV_BASIC.md` | B | B001–B999 | Directed bring-up: CSR identity, register read/write, single-command happy path per command class, log readback, upload ack generation |
| `DV_EDGE.md`  | E | E001–E999 | Boundary and stress: backpressure stalls, near-full/near-empty log FIFO, CDC corner cases, gts wrap, mask-combination matrix, atomic GTS snapshot |
| `DV_CROSS.md` | X | X001–X999 | Long mixed-axis runs that exercise cross-coverage cells (CSR activity vs command delivery, local_cmd vs synclink contention, mask × reset cmd, lvdspll_reset vs mm_reset timing, log FIFO occupancy crossings) |
| `DV_ERROR.md` | R | R001–R999 | Error injection and recovery: synclink parity/decode/loss_sync, unknown command byte, malformed payload truncation, mid-command reset, soft_reset / log_flush during traffic |

A separate `DV_HARNESS.md` describes the UVM environment, agents, scoreboard, and SVA bind modules. This DV_PLAN does not specify harness internals beyond names and references.

---

## 5. Coverage Model

The current standalone harness intentionally keeps **counter-based collectors**
instead of native `covergroup` constructs so coverage reports remain stable and
portable across toolchains. On this host the supported simulator is now
QuestaOne 2026 with native UVM DPI enabled, but `runctl_mgmt_cov` still records
coverage through explicit counters and `report_coverage()`. Randomization
remains LCG-based in `mutrig_common_pkg` for deterministic replay, and cross
bins are computed by tuple lookup rather than native `cross` constructs.

### 5.1 CSR coverage (collector: `cov_csr`)

| Bin group | Bins | Goal |
|-----------|------|------|
| `csr_addr_write` | one bin per writable word: 0x01, 0x02, 0x05, 0x13 (META selector, CONTROL, SCRATCH, LOCAL_CMD) | each ≥1 |
| `csr_addr_read`  | one bin per RO/RW word: 0x00..0x14 (21 bins) | each ≥1 |
| `csr_writeread_pair` | one bin per RW word: 0x01, 0x02, 0x05, 0x13 — sampled when a read after a write returns the written value | each ≥1 |
| `meta_page` | 4 bins, one per page selector (0..3) | each ≥1 |
| `scratch_pattern` | 4 bins: 0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555 | each ≥1 |
| `control_writeable_bits` | 4 bins: bit0=1, bit1=1, bit4=1, bit5=1 | each ≥1 |
| `control_mask_combo` | 4 bins: {dp,ct}={00,01,10,11} | each ≥1 |

### 5.2 Command coverage (collector: `cov_cmd`)

| Bin group | Bins | Goal |
|-----------|------|------|
| `cmd_byte_synclink` | 15 bins, one per defined byte (0x10–0x14, 0x20, 0x21, 0x24–0x26, 0x30–0x33, 0x40) | each ≥1 |
| `cmd_byte_local`    | 15 bins (same set, delivered via LOCAL_CMD) | each ≥1 |
| `cmd_byte_unknown`  | 1 bin: any byte not in the defined set | ≥1 |
| `cmd_payload_runprep` | 3 bins: run_number ∈ {0, mid, 0xFFFFFFFF} | each ≥1 |
| `cmd_payload_reset`   | 3 bins: assert_mask ∈ {0, mid, 0xFFFF} | each ≥1 |
| `cmd_payload_stop_reset` | 3 bins: release_mask ∈ {0, mid, 0xFFFF} | each ≥1 |
| `cmd_payload_address` | 3 bins: fpga_address ∈ {0, mid, 0xFFFF} | each ≥1 |
| `upload_ack_class`   | 2 bins: K30.7 (RUN_PREPARE), K29.7 (END_RUN) | each ≥1 |

### 5.3 Cross coverage (collector: `cov_cross`)

| ID | Axes | Cells | Goal |
|----|------|-------|------|
| C1 | synclink cmd class (15) × upload backpressure (3: continuous-ready, toggled, held-low) | 45 | ≥1 each |
| C2 | readyless runctl fanout path (2: synclink, LOCAL_CMD) × fanout class (2: emits, suppressed ADDRESS) | 4 | ≥1 each |
| C3 | CSR activity class (3: read, write, idle) × recv_state (4: IDLE, RX_PAYLOAD, POSTING, LOG_WR) | 12 | ≥1 each |
| C4 | log FIFO occupancy bin (5: empty, low<25%, mid, high>75%, near-full) × LOG_POP burst length (3: 1, 4, 16) | 15 | ≥1 each |
| C5 | rst_mask combo (4) × reset cmd class (2: CMD_RESET, CMD_STOP_RESET) | 8 | ≥1 each |
| C6 | lvdspll_reset × mm_reset ordering (3: lvds-first, mm-first, simultaneous) | 3 | ≥1 each |
| C7 | local_cmd submit phase (3: while recv idle, while recv RX_PAYLOAD, while recv POSTING) × command class (15) | 45 | ≥1 each |

Total cross cells: 102. Total CSR + command bins: 27 + 38 = 65. Coverage closure target: 100% of listed bins (167 in total).

### 5.4 Counter-collector mapping rules

- Each bin group is a `int unsigned <name>_hits[N]` array inside the collector class.
- A `sample_*()` task is invoked from monitors / scoreboard analysis hooks on every relevant transaction.
- `report_coverage()` is called from `report_phase()` of the env, prints a single-line summary per group, and prints `UNCOVERED: <group>[<idx>]` for every zero bin. Any non-zero `UNCOVERED` count fails signoff.
- LCG PRNG (`mutrig_common_pkg::lcg_next`) seeds payload values for the random sweeps; tests fix the seed via `+SEED=` to reproduce.

---

## 6. Test Case Catalog

Test ID convention: `<bucket><nnn>_<short_tag>` where bucket ∈ {B,E,X,R} and nnn is a 3-digit zero-padded ordinal. Each row has stimulus and expected result columns and a status column for tracking.

The tables below hold only the bring-up spine (B001–B022, E001–E020, X001–X015, R001–R017). IDs beyond those ranges live in the per-bucket files: `DV_BASIC.md` (B023–B100), `DV_EDGE.md` (E021–E102), `DV_CROSS.md` (X016–X100), `DV_ERROR.md` (R018–R100).

### 6.1 DV_BASIC (B-series)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B001_uid_read | Read CSR word 0x00 after reset | Returns 0x52434D48 (`RCMH`) | planned |
| B002_uid_write_ignored | Write 0xDEADBEEF to 0x00, read back | Read returns 0x52434D48 | planned |
| B003_meta_pages | Write 0,1,2,3 to META selector, read back each | 4 distinct page payloads observed | planned |
| B004_scratch_rw | Write 0xA5A5A5A5 to SCRATCH, read back | Read returns same value | planned |
| B005_control_mask_rw | Set CONTROL.rst_mask_dp / rst_mask_ct, read back | Reads reflect written values | planned |
| B006_status_idle_after_reset | Read STATUS after reset | recv_idle=1, host_idle=1, log_fifo_empty=1 | planned |
| B007_synclink_run_prepare | Send 0x10 + 4-byte run number on synclink | LAST_CMD=0x10, RUN_NUMBER matches, log entry queued, upload ack with K30.7 emitted | planned |
| B008_synclink_run_sync | Send 0x11 | runctl source emits 0x11, log entry queued | planned |
| B009_synclink_start_run | Send 0x12 | runctl source emits 0x12, log queued | planned |
| B010_synclink_end_run | Send 0x13 | runctl emits 0x13, upload ack with K29.7 emitted, log queued | planned |
| B011_synclink_abort_run | Send 0x14 | runctl emits 0x14, log queued | planned |
| B012_synclink_reset | Send 0x30 + 16-bit mask, masks=00 | dp_hard_reset and ct_hard_reset asserted, RESET_MASK[15:0] updated, log queued | planned |
| B013_synclink_stop_reset | Send 0x31 + 16-bit mask | dp/ct_hard_reset deasserted, RESET_MASK[31:16] updated | planned |
| B014_synclink_enable | Send 0x32 | runctl emits 0x32 | planned |
| B015_synclink_disable | Send 0x33 | runctl emits 0x33 | planned |
| B016_synclink_address | Send 0x40 + 16-bit address | FPGA_ADDRESS[15:0] updated, [31] sticky=1, runctl source NOT toggled | planned |
| B017_log_pop_4words | Run B007 then read LOG_POP four times | 4 sub-words match recv_ts/cmd/payload/exec_ts of B007 | planned |
| B018_rx_cmd_count | Send 8 commands, read RX_CMD_COUNT | Returns 8 | planned |
| B019_local_cmd_basic | Write LOCAL_CMD with 0x12000000 | runctl emits 0x12, RX_CMD_COUNT increments, log entry queued | planned |
| B020_gts_snapshot | Read GTS_L then GTS_H | GTS_H matches the upper bits captured at GTS_L read instant | planned |
| B021_ack_symbols_default | Read ACK_SYMBOLS | Returns {0xFD, 0xFE} packed | planned |
| B022_log_status_empty | Read LOG_STATUS after reset | rdempty=1, rdusedw=0 | planned |

### 6.2 DV_EDGE (E-series)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| E001_runctl_readyless_broadcast | Send synclink cmd to readyless runctl stream | host emits one valid beat and retires without downstream handshake | planned |
| E002_upload_ready_held_low | Send RUN_PREPARE while upload ready=0 for 128 cycles | upload FSM stalls; on release, exactly one ack packet emitted | planned |
| E003_back_to_back_cmds | Stream 16 RUN_SYNC bytes back-to-back | All 16 fan out, RX_CMD_COUNT=16, log FIFO holds 16 entries | planned |
| E004_log_fifo_near_full | Submit commands until LOG_STATUS.rdusedw approaches max | rdfull asserts; further commands continue but oldest log entries hold (RTL behavior verified) | planned |
| E005_log_pop_burst | Pop 64 sub-words back-to-back | All sub-words match scoreboard sequence | planned |
| E006_meta_invalid_page | Write META selector with reserved bits set | Lower 2 bits select page; upper bits ignored | planned |
| E007_control_mask_dp_only | Set rst_mask_dp=1, send CMD_RESET | `dp_hard_reset` suppressed, `ct_hard_reset` asserted, `ext_hard_reset` pulses | planned |
| E008_control_mask_ct_only | Set rst_mask_ct=1, send CMD_RESET | `ct_hard_reset` suppressed, `dp_hard_reset` asserted, `ext_hard_reset` pulses | planned |
| E009_control_mask_both | Set both masks, send CMD_RESET | Local `dp_hard_reset` / `ct_hard_reset` stay deasserted, `ext_hard_reset` still pulses; RESET_MASK CSR still updated | planned |
| E010_gts_wrap | Run 48-bit gts to upper boundary, send command | recv_ts/exec_ts capture wrap correctly across word boundary | planned |
| E011_address_no_fanout | Send 0x40 ADDRESS, monitor runctl | runctl source has zero transactions during address handling | planned |
| E012_runctl_readyless_burst | Send long sequence on readyless runctl stream | All commands accepted, one-cycle fanout beats observed, no drops | planned |
| E013_local_cmd_busy_block | Issue 2 LOCAL_CMD writes back-to-back without polling busy | Second write while local_cmd_busy=1 is dropped/ignored (per spec) | planned |
| E014_soft_reset_idle | Pulse CONTROL.soft_reset while idle | All FSMs return to IDLE, snapshots cleared, log retained or flushed per spec | planned |
| E015_log_flush | Pulse CONTROL.log_flush after queueing 5 entries | LOG_STATUS.rdempty asserts, LOG_POP returns 0 | planned |
| E016_rx_err_count_increment | Inject one parity error on synclink | RX_ERR_COUNT increments by 1, no command delivered | planned |
| E017_unknown_command | Send byte 0x77 (undefined) | RTL ignores or counts it (per spec); no fanout, no log entry, no upload ack | planned |
| E018_atomic_gts_two_readers | Two interleaved GTS_L/GTS_H read pairs from a sequencer | Each pair is internally consistent (no torn 48-bit value) | planned |
| E019_status_state_encoding | Stall recv FSM in RX_PAYLOAD by withholding next byte; read STATUS | recv_state_enc reflects RX_PAYLOAD encoding | planned |
| E020_runctl_no_ready_port | Elaborate/package readyless runctl source | No `aso_runctl_ready` port exists and no runctl POSTING stall is possible | planned |

Implementation note (`2026-04-22`):
the current tree also carries a direct standalone test
`runctl_mgmt_host_local_cmd_backpressure_test`. It is the canonical reproducer
for `BUG-001-R` and covers the held `LOCAL_CMD` / busy-clear / waitrequest
subcase closest to `E097_local_cmd_busy_timing` and
`E098_csr_waitrequest_release`. It does not replace the still-planned explicit
two-write rejection case `E013_local_cmd_busy_block`.

### 6.3 DV_CROSS (X-series)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X001_csr_traffic_during_cmd | Random CSR reads to STATUS/RECV_TS/LAST_CMD while sending mixed commands | All commands accepted; CSR readbacks self-consistent | planned |
| X002_csr_writes_during_cmd | Random CSR writes to SCRATCH and CONTROL while sending commands | No interference; commands all delivered | planned |
| X003_local_cmd_vs_synclink | Issue LOCAL_CMD while synclink command in flight | Both commands eventually serialize through recv FSM in defined order | planned |
| X004_mask_combo_sweep | Iterate 4 mask combos × CMD_RESET / CMD_STOP_RESET pairs | Local `dp/ct` outputs match the mask truth table for all 8 combinations; exported `ext_hard_reset` pulses on RESET and can be cancelled by STOP_RESET independent of mask | planned |
| X005_log_fill_drain_mix | Random fill/drain sequence touching empty/low/mid/high/near-full bins | Cov bin C4 fully covered; scoreboard agrees on all popped sub-words | planned |
| X006_upload_backpressure_mix | All 10 command classes × 3 upload backpressure modes | Cov bin C1 (30 cells) fully covered; ack packets correct | planned |
| X007_runctl_readyless_fanout | Sweep synclink/LOCAL_CMD fanout and ADDRESS suppression | Cov bin C2 fully covered; FSM never waits for downstream ready | planned |
| X008_dual_reset_lvds_first | Assert lvdspll_reset before mm_reset | Both domains return to a clean idle, all CSRs at default | planned |
| X009_dual_reset_mm_first | Assert mm_reset before lvdspll_reset | Same as X008 | planned |
| X010_dual_reset_simul | Assert both resets simultaneously | Same as X008 | planned |
| X011_local_cmd_phase_mix | LOCAL_CMD submit while recv FSM in IDLE / RX_PAYLOAD / POSTING | Cov bin C7 fully covered; toggle handshake CDC clean | planned |
| X012_long_random_run | 5000 mixed-command run with random payloads from LCG PRNG | All counters, RX_CMD_COUNT, RX_ERR_COUNT, log entries match scoreboard | planned |
| X013_log_pop_burst_during_cmd | LOG_POP burst of 16 sub-words concurrent with synclink RUN_PREPARE traffic | LOG_POP returns correct sub-words; new entries enqueue without loss | planned |
| X014_meta_sweep_during_cmd | Cycle META selector across 4 pages while commands flow | META reads return correct page each time, no command interference | planned |
| X015_scratch_pattern_during_cmd | Write SCRATCH with 4 patterns interleaved with command stream | Cov bin csr scratch_pattern fully covered | planned |

### 6.4 DV_ERROR (R-series)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| R001_synclink_parity_error | Inject error[1]=1 on a command byte | Byte dropped, RX_ERR_COUNT++, no fanout, recv FSM returns to IDLE | planned |
| R002_synclink_decode_error | Inject error[0]=1 | Same as R001 | planned |
| R003_synclink_loss_sync | Inject error[2]=1 mid-command | Recv FSM aborts current command, returns to IDLE, RX_ERR_COUNT++ | planned |
| R004_unknown_cmd_byte | Send 0x77 then 0x10+payload | First ignored, second processed normally | planned |
| R005_truncated_run_prepare | Send 0x10 then drop valid before 4 payload bytes complete; later restart with valid bytes | Recv FSM either times out per spec or completes when stream resumes; no spurious log entry | planned |
| R006_truncated_reset | Same as R005 for CMD_RESET (16b payload) | Same | planned |
| R007_mid_cmd_lvdspll_reset | Send 0x10 then assert lvdspll_reset mid-payload | All recv state cleared, no log entry, no upload ack | planned |
| R008_mid_cmd_mm_reset | Send 0x10 then assert mm_reset only | Lvdspll datapath continues; CSR reset to defaults; log FIFO mm-side state cleared per spec | planned |
| R009_soft_reset_during_cmd | Pulse CONTROL.soft_reset mid-command | All FSMs go to IDLE, partial command discarded, no spurious outputs | planned |
| R010_log_flush_during_cmd | Pulse CONTROL.log_flush while a log entry is being written | No torn entry; either entire entry present or absent | planned |
| R011_local_cmd_during_busy | Issue LOCAL_CMD twice with no busy poll | Second write rejected per spec; STATUS.local_cmd_busy correctly tracks | planned |
| R012_runctl_ready_removed | Attempt to instantiate a runctl-ready sink path | Compile/elaboration rejects stale ready wiring; readyless broadcast still processes next command | planned |
| R013_upload_ready_stuck_low | Hold upload ready low after RUN_PREPARE | Upload FSM stalls; subsequent cmds may or may not stall per spec; recovery on release | planned |
| R014_log_fifo_full_overflow | Push more commands than log FIFO depth without popping | LOG_STATUS.rdfull asserts; behavior (drop oldest vs block new) verified against spec | planned |
| R015_csr_addr_oob | Read/write CSR word 0x1F (out of range) | RTL returns 0 / write ignored, no waitrequest | planned |
| R016_simultaneous_cmd_and_err | Inject parity error on every other byte while streaming valid commands | Valid commands counted, errored bytes counted separately, no cross-contamination | planned |
| R017_recovery_after_loss_sync | After R003, send a clean command sequence | All subsequent commands processed normally | planned |

Total planned test IDs: 100 (B001–B100) + 102 (E001–E102) + 100 (X001–X100) + 100 (R001–R100) = **402**.

Detailed long-form B/E/X/R cards are held in `DV_BASIC.md`, `DV_EDGE.md`, `DV_CROSS.md`, `DV_ERROR.md`. This section lists only the bring-up spine; the per-bucket files are authoritative for the expanded IDs.

---

## 6.5 Frozen RTL Behaviors (reconciled from RTL review)

These lock down behaviors the bucket files and scoreboard assume. Verified against `rtl/runctl_mgmt_host.sv` on 2026-04-13.

| # | Behavior | Source line | Test binding |
|---|----------|-------------|--------------|
| F1 | `loss_sync` (error[2]) on an **idle** byte is silently ignored: gate is outside the error-count branch in `RECV_IDLE`. It does **not** increment `RX_ERR_COUNT`. | recv FSM ~L438 | R001/R003/R016: only count errors on non-idle bytes |
| F2 | Unknown command bytes go `RECV_IDLE → RECV_CLEANUP` without setting `ev_cmd_accepted`: **`RX_CMD_COUNT` does not increment** for unknown bytes. Applies to both synclink and LOCAL_CMD paths. | recv FSM ~L432–435, ~L448–450 | B018/R004/R038–R052: scoreboard expects no RX_CMD_COUNT delta on unknown |
| F3 | `CMD_ADDRESS` (0x40) is treated as a known command and **does** increment `RX_CMD_COUNT`, but does not fan out to the runctl source. | host FSM address branch | B018 total count, E011, X001 |
| F4 | Parity/decode error priority: `loss_sync` dominates, and each errored **non-idle** byte produces exactly one `RX_ERR_COUNT` increment. | recv FSM ~L461 | R001/R002/R003 |
| F5 | k-flag received **mid-payload** is silently dropped without advancing the FSM (no else branch). | recv FSM ~L467 | R053–R062 |
| F6 | No payload watchdog, no resync-on-command-byte in `RECV_RX_PAYLOAD`: a command byte received mid-payload is shifted in as data (aliasing hazard — **known limitation**, not an RTL bug gate for this release). | recv FSM `RECV_RX_PAYLOAD` | R058 documents, does not fail |
| F7 | Log FIFO drop policy is **drop-new** on write-side full, not drop-oldest. `LOG_DROP_COUNT` increments once per dropped log entry. | recv log-write ~L515–526 | R014, B018 delta tracking |
| F8 | `soft_reset` drains **both** FIFO sides (lvds write side via `lvds_fsm_rst`, mm read side via `CSR_LOG_FLUSH`). | CSR FSM + lvds reset | R009, E015 |
| F9 | CSR OOB / RO writes take exactly one cycle to accept and have **no side effects**; readdata=0. | CSR FSM default arm | R015/R063–R077 |
| F10 | CSR same-cycle `read` + `write` (both asserted): **write wins** (`if(write) … else if(read) …`). | CSR FSM ~L928 | R066 |
| F11 | Upload backpressure **does** back-propagate to recv for `RUN_PREPARE` and `END_RUN` because `pipe_r2h_done` gates on host FSM completion which waits for the upload emit. Other commands are decoupled. | host FSM pipe_r2h_done | R013, E002, X006 |

---

## 7. Signoff Criteria

- All 402 test IDs in the B/E/X/R buckets are implemented and PASS.
- Counter-based functional coverage: 100% of the 167 listed bins (CSR 27, command 38, cross 102) hit at least once. The `report_coverage()` task prints zero `UNCOVERED:` lines.
- No SVA assertion firings (`sva_*` bind modules in `tb/uvm/sva/`) across the full regression.
- No `UVM_ERROR` / `UVM_FATAL`. Scoreboard agrees on every CSR read, every log sub-word, every upload ack, and every runctl fanout transaction.
- Three-layer RTL lint (Questa source lint, Questa elaboration check, Quartus Design Assistant) clean. CDC review of all toggle/gray-code paths between `mm_clk` and `lvdspll_clk` documented and signed off.
- No simulator hangs across regression. Maximum test run-time bounded by an env-level watchdog.

---

## 8. Dependencies

- **Harness:** `tb/DV_HARNESS.md` (planned) — UVM environment topology, agent classes, scoreboard, SVA modules. This DV plan does not over-specify component internals.
- **Expected UVM components** (names only; structure deferred to DV_HARNESS):
  - `runctl_mgmt_env_pkg.sv` — env package
  - `synclink_agent` — AVST sink driver/monitor for the synclink port
  - `runctl_sink_agent` — readyless AVST monitor for the runctl port
  - `upload_sink_agent` — AVST source backpressure model for the upload port
  - `csr_agent` — AVMM master agent on the mm_clk side
  - `runctl_mgmt_scoreboard` — reference model for CSR shadow, log FIFO, upload acks, runctl fanout
  - `runctl_mgmt_cov` — counter-based coverage collector implementing section 5
  - `sva_synclink`, `sva_runctl`, `sva_upload`, `sva_csr`, `sva_cdc` — SVA bind modules
- **Simulator:** QuestaOne 2026 (`/data1/questaone_sim/questasim`). The active
  standalone rerun path uses native UVM 1.2 with DPI enabled. Historical FSE
  Starter constraints in older notes are no longer the active runtime model on
  this host.
- **Current migration evidence (2026-04-21):** `make -C tb run_uvm_smoke`
  passes on the supported QuestaOne path. Treat broader bucket-pass statements
  elsewhere in this planning document as historical intent unless they are
  backed by refreshed generated reports in the live tree.
- **Style:** `doc/STYLE.md` in this repo for test ID format and RTL coding rules. Cross-references: `histogram_statistics/tb/DV_PLAN.md`, `slow-control_hub/tb/DV_PLAN.md`.
- **Legacy reference:** `legacy/runctl_mgmt_host_v24.vhd` for synclink/runctl/upload datapath semantics (CSR block is fully respecified in section 3 of this document).
