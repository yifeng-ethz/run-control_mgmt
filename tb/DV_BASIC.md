# runctl_mgmt_host DV -- Basic Functional Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** B001-B999
**Total:** 100 cases (B001-B022 detailed in sections 1-5; B023-B100 compact table in section 7)

This document expands every B-bucket entry in `DV_PLAN.md` section 6.1 into a directed test specification. It is the driver-facing elaboration of the plan: each case lists the exact CSR and AVST stimulus sequence, the expected scoreboard observations, and the coverage bins the test is expected to hit. IDs, order, and stimulus/expected intent are frozen to the plan. Any deviation is flagged in the "Plan drift notes" section at the end.

**CSR map reference (DV_PLAN section 3):**

| Word | Name | | Word | Name | | Word | Name |
|------|------|-|------|------|-|------|------|
| 0x00 | UID          | | 0x08 | FPGA_ADDRESS | | 0x10 | RX_ERR_COUNT |
| 0x01 | META         | | 0x09 | RECV_TS_L    | | 0x11 | LOG_STATUS   |
| 0x02 | CONTROL      | | 0x0A | RECV_TS_H    | | 0x12 | LOG_POP      |
| 0x03 | STATUS       | | 0x0B | EXEC_TS_L    | | 0x13 | LOCAL_CMD    |
| 0x04 | LAST_CMD     | | 0x0C | EXEC_TS_H    | | 0x14 | ACK_SYMBOLS  |
| 0x05 | SCRATCH      | | 0x0D | GTS_L        | |      |              |
| 0x06 | RUN_NUMBER   | | 0x0E | GTS_H        | |      |              |
| 0x07 | RESET_MASK   | | 0x0F | RX_CMD_COUNT | |      |              |

All tests run with the default harness topology: `synclink_agent` driving the AVST sink, `runctl_sink_agent` and `upload_sink_agent` terminating the AVST sources with ready permanently asserted unless the test states otherwise, and `csr_agent` on the AVMM slave. The scoreboard snapshots CSR shadow state and records every runctl / upload transaction for comparison.

---

## 1. CSR Identity (B001-B003)

These three tests prove the identity header of the IP. They must pass first; all downstream tests depend on the CSR bus being trustworthy.

---

### B001_uid_read

- **ID:** B001_uid_read
- **Category:** CSR header / UID
- **Goal:** Prove that CSR word 0x00 reads back the frozen UID `RCMH` after reset.
- **Setup:** Both `mm_reset` and `lvdspll_reset` released. No prior CSR activity. No synclink traffic.
- **Stimulus sequence:**
  1. Hold both resets for at least 16 clocks after power-on, then release.
  2. Wait 8 mm_clk cycles for the AVMM slave to become responsive.
  3. Issue a single AVMM read to word 0x00.
- **Expected result:**
  1. Read returns `0x52434D48` exactly (ASCII `RCMH`).
  2. The runctl AVST source emits zero transactions during the sequence.
  3. The upload AVST source emits zero transactions during the sequence.
- **Coverage bins hit:** `csr_addr_read[0x00]`
- **Pass criteria:**
  1. Readback value bit-exact equal to `0x52434D48`.
  2. `uvm_error_count == 0` at test end.
  3. Scoreboard reports zero runctl and zero upload transactions.
- **Status:** planned

---

### B002_uid_write_ignored

- **ID:** B002_uid_write_ignored
- **Category:** CSR header / UID read-only enforcement
- **Goal:** Prove that UID is hard-wired and any write is silently discarded by the decode.
- **Setup:** Post-reset idle state. No synclink or upload traffic.
- **Stimulus sequence:**
  1. Read UID (expect `RCMH`) to baseline.
  2. AVMM write `0xDEADBEEF` to word 0x00.
  3. Wait 4 mm_clk cycles.
  4. Read UID again.
- **Expected result:**
  1. Step 1 returns `0x52434D48`.
  2. Step 4 returns `0x52434D48` (write did not take).
  3. No waitrequest or slave error observed on the write.
  4. Zero runctl and zero upload transactions.
- **Coverage bins hit:** `csr_addr_read[0x00]`
- **Pass criteria:**
  1. Both reads bit-exact `0x52434D48`.
  2. AVMM bus remains responsive throughout.
- **Status:** planned

---

### B003_meta_pages

- **ID:** B003_meta_pages
- **Category:** CSR header / META page mux
- **Goal:** Prove that the META selector chooses among four distinct metadata pages (VERSION, DATE, GIT, INSTANCE_ID).
- **Setup:** Post-reset idle. HDL parameters `VERSION`, `DATE`, `GIT`, `INSTANCE_ID` set to their integration defaults and shadowed in the scoreboard.
- **Stimulus sequence:**

  | Step | Action |
  |------|--------|
  | 1 | Write `0x00000000` to META (page=0). |
  | 2 | Read META, capture value `v0`. |
  | 3 | Write `0x00000001` to META (page=1). |
  | 4 | Read META, capture value `v1`. |
  | 5 | Write `0x00000002` to META (page=2). |
  | 6 | Read META, capture value `v2`. |
  | 7 | Write `0x00000003` to META (page=3). |
  | 8 | Read META, capture value `v3`. |

- **Expected result:**
  1. `v0` equals the scoreboard VERSION constant (fields `[31:24]=MAJOR`, `[23:16]=MINOR`, `[15:12]=PATCH`, `[11:0]=BUILD`).
  2. `v1` equals the scoreboard DATE constant.
  3. `v2` equals the scoreboard GIT short-hash constant.
  4. `v3` equals the scoreboard INSTANCE_ID constant.
  5. All four values are pairwise distinct (sanity against a stuck-decoder bug).
  6. Zero runctl and zero upload activity.
- **Coverage bins hit:** `csr_addr_write[0x01]`, `csr_addr_read[0x01]`, `csr_writeread_pair[0x01]`, `meta_page[0]`, `meta_page[1]`, `meta_page[2]`, `meta_page[3]`
- **Pass criteria:**
  1. All four reads match their scoreboard expected constants.
  2. `{v0, v1, v2, v3}` are distinct.
- **Status:** planned

---

## 2. CSR Scratch and Control (B004-B005)

Read/write path sanity on the two RW words that are not command-driven.

---

### B004_scratch_rw

- **ID:** B004_scratch_rw
- **Category:** Scratch / CSR RW connectivity
- **Goal:** Prove that SCRATCH is a fully independent 32-bit RW register and that the CSR address decode routes to the correct word.
- **Setup:** Post-reset idle.
- **Stimulus sequence:**
  1. Read SCRATCH to record the reset default.
  2. Write `0xDEADBEEF` to SCRATCH.
  3. Read SCRATCH.
  4. Write `0xCAFEBABE` to SCRATCH.
  5. Read SCRATCH.
  6. Write `0xA5A5A5A5` to SCRATCH (the plan's nominal pattern).
  7. Read SCRATCH.
- **Expected result:**
  1. Step 3 returns `0xDEADBEEF`.
  2. Step 5 returns `0xCAFEBABE`.
  3. Step 7 returns `0xA5A5A5A5`.
  4. No write touches UID, META, CONTROL, or any status register (scoreboard shadow for those words is unchanged).
  5. Zero runctl and zero upload activity.
- **Coverage bins hit:** `csr_addr_write[0x05]`, `csr_addr_read[0x05]`, `csr_writeread_pair[0x05]`, plus whichever `scratch_pattern` bin matches `0xA5A5A5A5` (not listed in the plan's fixed 4-pattern set; see Plan drift notes).
- **Pass criteria:**
  1. Three distinct writes each read back bit-exact.
  2. No collateral CSR state change.
- **Status:** planned

---

### B005_control_mask_rw

- **ID:** B005_control_mask_rw
- **Category:** CONTROL / reset mask RW bits
- **Goal:** Prove that CONTROL bits [4] `rst_mask_dp` and [5] `rst_mask_ct` are RW and hold their written value.
- **Setup:** Post-reset idle. CONTROL = 0.
- **Stimulus sequence:**
  1. Write `0x00000010` to CONTROL (rst_mask_dp=1, rst_mask_ct=0).
  2. Read CONTROL.
  3. Write `0x00000020` to CONTROL (rst_mask_dp=0, rst_mask_ct=1).
  4. Read CONTROL.
  5. Write `0x00000030` to CONTROL (both masks=1).
  6. Read CONTROL.
  7. Write `0x00000000` to CONTROL.
  8. Read CONTROL.
- **Expected result:**
  1. Reads at steps 2/4/6/8 return `0x10`, `0x20`, `0x30`, `0x00` respectively.
  2. Bits [0] `soft_reset` and [1] `log_flush` always read as 0 (W1P, not storage).
  3. `dp_hard_reset` and `ct_hard_reset` conduit outputs stay deasserted (no RESET command has been received).
  4. Zero runctl / upload activity.
- **Coverage bins hit:** `csr_addr_write[0x02]`, `csr_addr_read[0x02]`, `csr_writeread_pair[0x02]`, `control_writeable_bits[bit4]`, `control_writeable_bits[bit5]`, `control_mask_combo[00]`, `control_mask_combo[01]`, `control_mask_combo[10]`, `control_mask_combo[11]`
- **Pass criteria:**
  1. All four readbacks match expected.
  2. W1P bits stay 0 on readback.
  3. `dp_hard_reset` / `ct_hard_reset` remain 0 throughout.
- **Status:** planned

---

## 3. STATUS at Reset (B006)

---

### B006_status_idle_after_reset

- **ID:** B006_status_idle_after_reset
- **Category:** STATUS / reset default
- **Goal:** Prove that after full reset both FSMs are in IDLE, the log FIFO is empty, and no hard reset is driven.
- **Setup:** Assert both resets, release, wait for CDC settling (at least 8 mm_clk and 8 lvdspll_clk cycles).
- **Stimulus sequence:**
  1. Read STATUS.
  2. Read LOG_STATUS.
- **Expected result:**
  1. STATUS bit[0] `recv_idle` = 1.
  2. STATUS bit[1] `host_idle` = 1.
  3. STATUS bit[4] `dp_hard_reset` = 0.
  4. STATUS bit[5] `ct_hard_reset` = 0.
  5. STATUS bit[30] `local_cmd_busy` = 0.
  6. STATUS bit[31] `log_fifo_empty` = 1.
  7. STATUS bits [15:8] and [23:16] both encode the IDLE state for recv and host FSMs respectively.
  8. LOG_STATUS bit[16] `rdempty` = 1 and bits[9:0] `rdusedw` = 0.
  9. Runctl AVST source idle, upload AVST source idle.
- **Coverage bins hit:** `csr_addr_read[0x03]`, `csr_addr_read[0x11]`
- **Pass criteria:**
  1. All nine expected observations hold at the read sample point.
- **Status:** planned

---

## 4. Synclink Command Happy Path (B007-B016)

One directed test per defined synclink command byte. Each test sends the command through the synclink AVST sink in the lvdspll_clk domain and verifies the CSR snapshot, the log FIFO entry, the runctl fanout (if any), and the upload ack (if any).

---

### B007_synclink_run_prepare

- **ID:** B007_synclink_run_prepare
- **Category:** Command decode / RUN_PREPARE
- **Goal:** Prove that a `CMD_RUN_PREPARE (0x10)` with a 32-bit run-number payload updates LAST_CMD, RUN_NUMBER, queues a 4-word log entry, and generates an upload ack packet with K30.7 (0xFE).
- **Setup:** Post-reset idle. `ACK_SYMBOLS` defaults (`RUN_START=0xFE`, `RUN_END=0xFD`). Runctl and upload sinks ready.
- **Stimulus sequence:**
  1. Read CSR `RX_CMD_COUNT` to record baseline `n0`.
  2. Drive synclink with command byte `0x10` (data[8]=0, data[7:0]=0x10).
  3. Drive four data bytes forming run_number `0x12345678` (endianness per synclink_recv).
  4. Wait for recv FSM to complete posting (poll STATUS until `recv_idle=1 && host_idle=1`, with timeout).
  5. Read LAST_CMD.
  6. Read RUN_NUMBER.
  7. Read RX_CMD_COUNT.
- **Expected result:**
  1. LAST_CMD[7:0] = `0x10`.
  2. RUN_NUMBER = `0x12345678`.
  3. RX_CMD_COUNT = `n0 + 1`.
  4. Runctl AVST source emits exactly one transaction carrying command byte `0x10` (the spec requires fanout for RUN_PREPARE).
  5. Upload AVST source emits exactly one packet with sop/eop. The ack byte equals `0xFE` (K30.7 k-flag set in data[35:32]).
  6. Log FIFO `rdusedw` has advanced by 4 (one log sentence).
- **Coverage bins hit:** `csr_addr_read[0x04]`, `csr_addr_read[0x06]`, `csr_addr_read[0x0F]`, `cmd_byte_synclink[0x10]`, `cmd_payload_runprep[mid]`, `upload_ack_class[K30.7]`
- **Pass criteria:**
  1. LAST_CMD, RUN_NUMBER, RX_CMD_COUNT match expected.
  2. Exactly one runctl transaction carrying `0x10`.
  3. Exactly one upload ack with `0xFE` and correct sop/eop.
  4. Log FIFO usedw advanced by 4.
- **Status:** planned

---

### B008_synclink_run_sync

- **ID:** B008_synclink_run_sync
- **Category:** Command decode / RUN_SYNC (fanout-only)
- **Goal:** Prove that `CMD_RUN_SYNC (0x11)` fans out on runctl with no payload and no upload ack.
- **Setup:** Post-reset idle.
- **Stimulus sequence:**
  1. Read RX_CMD_COUNT baseline `n0`.
  2. Drive synclink byte `0x11` (no payload follows).
  3. Wait for `recv_idle && host_idle`.
  4. Read LAST_CMD.
  5. Read RX_CMD_COUNT.
- **Expected result:**
  1. LAST_CMD[7:0] = `0x11`.
  2. RX_CMD_COUNT = `n0 + 1`.
  3. Runctl source emits exactly one transaction with data = `0x11`.
  4. Upload source emits zero transactions.
  5. Log FIFO usedw advanced by 4.
- **Coverage bins hit:** `csr_addr_read[0x04]`, `csr_addr_read[0x0F]`, `cmd_byte_synclink[0x11]`
- **Pass criteria:**
  1. LAST_CMD, RX_CMD_COUNT match.
  2. One runctl transaction with `0x11`, zero upload.
- **Status:** planned

---

### B009_synclink_start_run

- **ID:** B009_synclink_start_run
- **Category:** Command decode / START_RUN (fanout-only)
- **Goal:** Prove that `CMD_START_RUN (0x12)` fans out on runctl with no payload and no upload ack.
- **Setup:** Post-reset idle.
- **Stimulus sequence:**
  1. Read RX_CMD_COUNT baseline `n0`.
  2. Drive synclink byte `0x12`.
  3. Wait for idle.
  4. Read LAST_CMD.
  5. Read RX_CMD_COUNT.
- **Expected result:**
  1. LAST_CMD[7:0] = `0x12`.
  2. RX_CMD_COUNT = `n0 + 1`.
  3. Runctl emits one transaction with `0x12`.
  4. Upload emits zero transactions.
  5. Log FIFO usedw advanced by 4.
- **Coverage bins hit:** `csr_addr_read[0x04]`, `csr_addr_read[0x0F]`, `cmd_byte_synclink[0x12]`
- **Pass criteria:**
  1. LAST_CMD, RX_CMD_COUNT match; runctl carries `0x12`; no upload.
- **Status:** planned

---

### B010_synclink_end_run

- **ID:** B010_synclink_end_run
- **Category:** Command decode / END_RUN (with upload ack)
- **Goal:** Prove that `CMD_END_RUN (0x13)` fans out on runctl and generates an upload ack packet with K29.7 (0xFD).
- **Setup:** Post-reset idle.
- **Stimulus sequence:**
  1. Read RX_CMD_COUNT baseline `n0`.
  2. Drive synclink byte `0x13`.
  3. Wait for idle.
  4. Read LAST_CMD.
  5. Read RX_CMD_COUNT.
- **Expected result:**
  1. LAST_CMD[7:0] = `0x13`.
  2. RX_CMD_COUNT = `n0 + 1`.
  3. Runctl emits one transaction with `0x13`.
  4. Upload emits exactly one ack packet with ack byte `0xFD` (k-flag set), sop/eop framing correct.
  5. Log FIFO usedw advanced by 4.
- **Coverage bins hit:** `csr_addr_read[0x04]`, `csr_addr_read[0x0F]`, `cmd_byte_synclink[0x13]`, `upload_ack_class[K29.7]`
- **Pass criteria:**
  1. LAST_CMD, RX_CMD_COUNT match.
  2. One runctl, one upload ack with `0xFD`.
- **Status:** planned

---

### B011_synclink_abort_run

- **ID:** B011_synclink_abort_run
- **Category:** Command decode / ABORT_RUN (fanout-only)
- **Goal:** Prove that `CMD_ABORT_RUN (0x14)` fans out on runctl with no upload ack.
- **Setup:** Post-reset idle.
- **Stimulus sequence:**
  1. Read RX_CMD_COUNT baseline `n0`.
  2. Drive synclink byte `0x14`.
  3. Wait for idle.
  4. Read LAST_CMD.
  5. Read RX_CMD_COUNT.
- **Expected result:**
  1. LAST_CMD[7:0] = `0x14`.
  2. RX_CMD_COUNT = `n0 + 1`.
  3. Runctl emits one transaction with `0x14`.
  4. Upload emits zero transactions.
  5. Log FIFO usedw advanced by 4.
- **Coverage bins hit:** `csr_addr_read[0x04]`, `csr_addr_read[0x0F]`, `cmd_byte_synclink[0x14]`
- **Pass criteria:**
  1. LAST_CMD, RX_CMD_COUNT match; runctl carries `0x14`; no upload.
- **Status:** planned

---

### B012_synclink_reset

- **ID:** B012_synclink_reset
- **Category:** Command decode / CMD_RESET with hard_reset assertion
- **Goal:** Prove that `CMD_RESET (0x30)` with a 16-bit assert mask drives both `dp_hard_reset` and `ct_hard_reset` when both CONTROL masks are 0, and updates RESET_MASK[15:0].
- **Setup:** Post-reset idle. CONTROL = 0 (both rst_mask_dp and rst_mask_ct = 0).
- **Stimulus sequence:**
  1. Read CONTROL to confirm masks are 0.
  2. Drive synclink byte `0x30` followed by 16-bit payload `0xABCD` (two synclink bytes).
  3. Wait for idle.
  4. Sample STATUS.
  5. Read RESET_MASK.
  6. Read LAST_CMD.
- **Expected result:**
  1. STATUS bit[4] `dp_hard_reset` = 1 (live).
  2. STATUS bit[5] `ct_hard_reset` = 1 (live).
  3. RESET_MASK[15:0] = `0xABCD`.
  4. RESET_MASK[31:16] unchanged from reset default (0).
  5. LAST_CMD[7:0] = `0x30`.
  6. Runctl emits one transaction with `0x30` (fanout behaviour per plan command-byte table).
  7. Upload emits zero transactions.
  8. Log FIFO usedw advanced by 4; log payload word encodes `{assert_mask, release_mask}` with assert=`0xABCD`.
- **Coverage bins hit:** `csr_addr_read[0x02]`, `csr_addr_read[0x03]`, `csr_addr_read[0x04]`, `csr_addr_read[0x07]`, `cmd_byte_synclink[0x30]`, `cmd_payload_reset[mid]`, `control_mask_combo[00]`
- **Pass criteria:**
  1. Both `dp_hard_reset` and `ct_hard_reset` asserted in the lvdspll_clk domain.
  2. RESET_MASK[15:0] = `0xABCD`.
  3. LAST_CMD correct; one log entry; no upload ack.
- **Status:** planned

---

### B013_synclink_stop_reset

- **ID:** B013_synclink_stop_reset
- **Category:** Command decode / CMD_STOP_RESET
- **Goal:** Prove that `CMD_STOP_RESET (0x31)` with a 16-bit release mask deasserts both hard_reset outputs and updates RESET_MASK[31:16].
- **Setup:** Run B012 first so that `dp_hard_reset` and `ct_hard_reset` are asserted and RESET_MASK[15:0] = `0xABCD`. Keep CONTROL masks = 0.
- **Stimulus sequence:**
  1. Confirm STATUS[4]=1 and STATUS[5]=1 (pre-condition).
  2. Drive synclink byte `0x31` followed by 16-bit payload `0x5A5A`.
  3. Wait for idle.
  4. Sample STATUS.
  5. Read RESET_MASK.
  6. Read LAST_CMD.
- **Expected result:**
  1. STATUS bit[4] `dp_hard_reset` = 0.
  2. STATUS bit[5] `ct_hard_reset` = 0.
  3. RESET_MASK[15:0] = `0xABCD` (unchanged from B012).
  4. RESET_MASK[31:16] = `0x5A5A`.
  5. LAST_CMD[7:0] = `0x31`.
  6. Runctl emits one transaction with `0x31`.
  7. Upload emits zero transactions.
  8. Log FIFO usedw advanced by 4.
- **Coverage bins hit:** `csr_addr_read[0x03]`, `csr_addr_read[0x04]`, `csr_addr_read[0x07]`, `cmd_byte_synclink[0x31]`, `cmd_payload_stop_reset[mid]`
- **Pass criteria:**
  1. Both hard_reset outputs deasserted.
  2. RESET_MASK[31:16] = `0x5A5A`; RESET_MASK[15:0] preserved.
- **Status:** planned

---

### B014_synclink_enable

- **ID:** B014_synclink_enable
- **Category:** Command decode / ENABLE (fanout-only)
- **Goal:** Prove that `CMD_ENABLE (0x32)` fans out on runctl with no side-effect on reset outputs or upload.
- **Setup:** Post-reset idle.
- **Stimulus sequence:**
  1. Read RX_CMD_COUNT baseline `n0`.
  2. Drive synclink byte `0x32`.
  3. Wait for idle.
  4. Read LAST_CMD.
  5. Read RX_CMD_COUNT.
  6. Sample STATUS.
- **Expected result:**
  1. LAST_CMD[7:0] = `0x32`.
  2. RX_CMD_COUNT = `n0 + 1`.
  3. Runctl emits one transaction with `0x32`.
  4. STATUS[4] and STATUS[5] remain 0.
  5. Upload emits zero transactions.
  6. Log FIFO usedw advanced by 4.
- **Coverage bins hit:** `csr_addr_read[0x03]`, `csr_addr_read[0x04]`, `csr_addr_read[0x0F]`, `cmd_byte_synclink[0x32]`
- **Pass criteria:**
  1. LAST_CMD, RX_CMD_COUNT match; runctl carries `0x32`; no upload; no hard_reset change.
- **Status:** planned

---

### B015_synclink_disable

- **ID:** B015_synclink_disable
- **Category:** Command decode / DISABLE (fanout-only)
- **Goal:** Prove that `CMD_DISABLE (0x33)` fans out on runctl with no other side effects.
- **Setup:** Post-reset idle.
- **Stimulus sequence:**
  1. Read RX_CMD_COUNT baseline `n0`.
  2. Drive synclink byte `0x33`.
  3. Wait for idle.
  4. Read LAST_CMD.
  5. Read RX_CMD_COUNT.
- **Expected result:**
  1. LAST_CMD[7:0] = `0x33`.
  2. RX_CMD_COUNT = `n0 + 1`.
  3. Runctl emits one transaction with `0x33`.
  4. Upload emits zero transactions.
  5. Log FIFO usedw advanced by 4.
- **Coverage bins hit:** `csr_addr_read[0x04]`, `csr_addr_read[0x0F]`, `cmd_byte_synclink[0x33]`
- **Pass criteria:**
  1. LAST_CMD, RX_CMD_COUNT match; runctl carries `0x33`.
- **Status:** planned

---

### B016_synclink_address

- **ID:** B016_synclink_address
- **Category:** Command decode / ADDRESS latch (no fanout)
- **Goal:** Prove that `CMD_ADDRESS (0x40)` with a 16-bit payload latches FPGA_ADDRESS and sets the sticky valid bit, and does NOT fan out on runctl.
- **Setup:** Post-reset idle. FPGA_ADDRESS = 0.
- **Stimulus sequence:**
  1. Read FPGA_ADDRESS to confirm `0`.
  2. Drive synclink byte `0x40` followed by 16-bit payload `0xBEEF`.
  3. Wait for idle.
  4. Read FPGA_ADDRESS.
  5. Read LAST_CMD.
- **Expected result:**
  1. FPGA_ADDRESS[15:0] = `0xBEEF`.
  2. FPGA_ADDRESS[31] `valid-sticky` = 1.
  3. LAST_CMD[7:0] = `0x40`; LAST_CMD[31:16] = `0xBEEF`.
  4. Runctl AVST source emits zero transactions during the whole sequence.
  5. Upload AVST source emits zero transactions.
  6. Log FIFO usedw advanced by 4 (command still logged even though no runctl fanout).
- **Coverage bins hit:** `csr_addr_read[0x04]`, `csr_addr_read[0x08]`, `cmd_byte_synclink[0x40]`, `cmd_payload_address[mid]`
- **Pass criteria:**
  1. FPGA_ADDRESS and LAST_CMD match expected.
  2. Zero runctl transactions, zero upload transactions.
- **Status:** planned

---

## 5. Log Readback, Counters, and Local_cmd (B017-B022)

---

### B017_log_pop_4words

- **ID:** B017_log_pop_4words
- **Category:** Log FIFO / 4-word sentence readback
- **Goal:** Prove that reading LOG_POP four times returns the four-word log sentence for the last command in the order `{ts_hi, ts_lo+cmd, payload, exec_ts_lo}` (per DV_PLAN section 3.6).
- **Setup:** Run the B007 stimulus (RUN_PREPARE with run_number `0x12345678`) as an inline pre-stage. Scoreboard captures `recv_ts`, `exec_ts`, `run_command=0x10`, `payload=0x12345678` at RTL dispatch.
- **Stimulus sequence:**
  1. Pre-stage: send `0x10` + run_number `0x12345678` on synclink (as in B007).
  2. Wait for idle.
  3. Read LOG_STATUS; capture `rdusedw` and verify `rdempty=0`.
  4. Read LOG_POP four times, storing `w0`, `w1`, `w2`, `w3`.
  5. Read LOG_STATUS again.
- **Expected result:**
  1. `w0[31:0]` = `recv_ts[47:16]`.
  2. `w1[31:16]` = `recv_ts[15:0]`.
  3. `w1[15:8]` = 0 (reserved).
  4. `w1[7:0]` = `0x10` (run_command byte).
  5. `w2` = `0x12345678` (run_number payload).
  6. `w3` = `exec_ts[31:0]`.
  7. LOG_STATUS after pop has `rdusedw` reduced by 4 and `rdempty=1` if this was the only entry.
  8. No spurious runctl or upload activity during the pop reads.
- **Coverage bins hit:** `csr_addr_read[0x11]`, `csr_addr_read[0x12]`, `cmd_byte_synclink[0x10]`, `upload_ack_class[K30.7]`
- **Pass criteria:**
  1. All four sub-words match the scoreboard record bit-exact.
  2. LOG_STATUS `rdusedw` delta = 4.
- **Status:** planned

---

### B018_rx_cmd_count

- **ID:** B018_rx_cmd_count
- **Category:** Counter / RX_CMD_COUNT
- **Goal:** Prove that `RX_CMD_COUNT` increments by exactly one per accepted synclink command across a small mixed batch of eight commands.
- **Setup:** Post-reset idle. Scoreboard baseline `RX_CMD_COUNT = 0`.
- **Stimulus sequence:**
  1. Read RX_CMD_COUNT baseline.
  2. Send the following eight synclink commands in order (no errors injected):

     | Order | Cmd  | Payload |
     |-------|------|---------|
     | 1 | 0x11 | none |
     | 2 | 0x12 | none |
     | 3 | 0x10 | 0x00000000 |
     | 4 | 0x13 | none |
     | 5 | 0x32 | none |
     | 6 | 0x33 | none |
     | 7 | 0x40 | 0x1234 |
     | 8 | 0x14 | none |

  3. After each command, wait for `recv_idle && host_idle`.
  4. Read RX_CMD_COUNT.
- **Expected result:**
  1. RX_CMD_COUNT at end = baseline + 8.
  2. Runctl sink receives seven transactions (all except `0x40`).
  3. Upload sink receives two ack packets (one for `0x10` with `0xFE`, one for `0x13` with `0xFD`).
  4. Log FIFO usedw advanced by 32 (8 sentences × 4 sub-words).
- **Coverage bins hit:** `csr_addr_read[0x0F]`, `cmd_byte_synclink[0x10]`, `cmd_byte_synclink[0x11]`, `cmd_byte_synclink[0x12]`, `cmd_byte_synclink[0x13]`, `cmd_byte_synclink[0x14]`, `cmd_byte_synclink[0x32]`, `cmd_byte_synclink[0x33]`, `cmd_byte_synclink[0x40]`, `cmd_payload_runprep[0]`, `cmd_payload_address[mid]`, `upload_ack_class[K30.7]`, `upload_ack_class[K29.7]`
- **Pass criteria:**
  1. RX_CMD_COUNT delta = 8.
  2. Scoreboard runctl count = 7, upload ack count = 2.
- **Status:** planned

---

### B019_local_cmd_basic

- **ID:** B019_local_cmd_basic
- **Category:** Local command injection / toggle-handshake CDC
- **Goal:** Prove that writing LOCAL_CMD in the mm_clk domain injects a command on the lvdspll_clk side that is indistinguishable from a synclink command at the runctl output, and that RX_CMD_COUNT increments.
- **Setup:** Post-reset idle. `STATUS.local_cmd_busy = 0`.
- **Stimulus sequence:**
  1. Read RX_CMD_COUNT baseline `n0`.
  2. Read STATUS to confirm `local_cmd_busy=0`.
  3. Write LOCAL_CMD with `0x12000000` (START_RUN, opcode `0x12` in upper byte, payload zero).
  4. Poll STATUS until `local_cmd_busy=0` again (handshake complete).
  5. Wait for `recv_idle && host_idle`.
  6. Read LAST_CMD.
  7. Read RX_CMD_COUNT.
  8. Read LOCAL_CMD to confirm it returns the last-written word.
- **Expected result:**
  1. LAST_CMD[7:0] = `0x12`.
  2. RX_CMD_COUNT = `n0 + 1`.
  3. LOCAL_CMD read returns `0x12000000`.
  4. Runctl emits exactly one transaction with `0x12`.
  5. Upload emits zero transactions.
  6. Log FIFO usedw advanced by 4.
  7. `STATUS.local_cmd_busy` was observed high at least once during the handshake window, then returned to 0.
- **Coverage bins hit:** `csr_addr_write[0x13]`, `csr_addr_read[0x13]`, `csr_writeread_pair[0x13]`, `csr_addr_read[0x03]`, `csr_addr_read[0x04]`, `csr_addr_read[0x0F]`, `cmd_byte_local[0x12]`
- **Pass criteria:**
  1. LAST_CMD, RX_CMD_COUNT, LOCAL_CMD readback all match.
  2. Runctl emits one `0x12`; no upload.
  3. `local_cmd_busy` rising edge observed.
- **Status:** planned

---

### B020_gts_snapshot

- **ID:** B020_gts_snapshot
- **Category:** GTS atomic snapshot
- **Goal:** Prove that reading GTS_L atomically latches the upper 16 bits of the live 48-bit gts counter into GTS_H, so that a GTS_L + GTS_H pair forms a consistent 48-bit value.
- **Setup:** Post-reset idle. `gts_counter` is free-running in the lvdspll_clk domain (reset only by `lvdspll_reset`). Allow at least a few thousand lvdspll clocks to accumulate so that neither half is zero.
- **Stimulus sequence:**
  1. Wait 4096 lvdspll_clk cycles after reset release for the GTS to advance.
  2. Read GTS_L; record `gts_lo`.
  3. Read GTS_H; record `gts_hi`.
  4. Repeat steps 2-3 after another 4096 cycles to get a second pair `(gts_lo2, gts_hi2)`.
- **Expected result:**
  1. First read of GTS_L triggers an internal latch of the upper 16 bits at the same lvdspll_clk edge (after CDC).
  2. `{gts_hi, gts_lo}` as a 48-bit value corresponds to a gts sample that was valid at the moment of the GTS_L read (scoreboard shadow compares within a bounded CDC uncertainty window).
  3. `{gts_hi2, gts_lo2}` > `{gts_hi, gts_lo}` (counter is advancing monotonically).
  4. No runctl / upload activity triggered by GTS reads.
- **Coverage bins hit:** `csr_addr_read[0x0D]`, `csr_addr_read[0x0E]`
- **Pass criteria:**
  1. Both 48-bit samples fall inside the scoreboard's acceptance window and are strictly increasing.
  2. GTS_H read without a prior GTS_L read in the same test episode returns the value latched by the most recent GTS_L read (not the live upper bits).
- **Status:** planned

---

### B021_ack_symbols_default

- **ID:** B021_ack_symbols_default
- **Category:** CSR / parameter mirror
- **Goal:** Prove that the ACK_SYMBOLS CSR exposes the integration-time parameters for the RUN_START and RUN_END ack k-symbols.
- **Setup:** Post-reset idle. HDL parameters left at defaults `RUN_START_ACK_SYMBOL=0xFE`, `RUN_END_ACK_SYMBOL=0xFD`.
- **Stimulus sequence:**
  1. Read ACK_SYMBOLS.
- **Expected result:**
  1. ACK_SYMBOLS[7:0] = `0xFE`.
  2. ACK_SYMBOLS[15:8] = `0xFD`.
  3. ACK_SYMBOLS[31:16] = 0 or the documented reserved value.
  4. Zero runctl / upload activity.
- **Coverage bins hit:** `csr_addr_read[0x14]`
- **Pass criteria:**
  1. ACK_SYMBOLS reads back `0x0000FDFE` (little-endian packing per the plan field ordering).
- **Status:** planned

---

### B022_log_status_empty

- **ID:** B022_log_status_empty
- **Category:** Log FIFO / reset-default empty
- **Goal:** Prove that LOG_STATUS reports an empty FIFO immediately after reset and LOG_POP returns 0.
- **Setup:** Post-reset idle. No commands have been sent.
- **Stimulus sequence:**
  1. Read LOG_STATUS.
  2. Read LOG_POP.
  3. Read LOG_STATUS again.
- **Expected result:**
  1. Step 1: `rdempty=1`, `rdfull=0`, `rdusedw=0`.
  2. Step 2: returns `0x00000000` (read-on-empty returns 0 per spec).
  3. Step 3 identical to step 1 (empty read does not disturb the counters).
  4. STATUS bit[31] `log_fifo_empty` reads 1 when sampled.
  5. Zero runctl / upload activity.
- **Coverage bins hit:** `csr_addr_read[0x11]`, `csr_addr_read[0x12]`
- **Pass criteria:**
  1. Both LOG_STATUS reads identical with `rdempty=1` and `rdusedw=0`.
  2. LOG_POP returns `0x00000000`.
- **Status:** planned

---

## 6. Extended bring-up cases (B023-B100)

This section adds 78 compact directed smoke cases that cover every CSR word at reset, every RW word write/read path, every command byte via both synclink and LOCAL_CMD, upload ack packet formation, per-command log entry layout, GTS atomic snapshot corner smoke, STATUS field encoding, counter saturation smoke, W1P pulse behavior, reserved-bit masking, ACK_SYMBOLS visibility, and every frozen RTL decision documented in the DV_PLAN preamble. Rows use the compact `| ID | Stimulus | Expected | Status |` form. Unless noted, each row is self-contained, starts from a released-reset idle state, leaves runctl/upload sinks with ready permanently high, and relies on the default `runctl_mgmt_env` topology.

### 6.1 Per-word reset-value reads (B023-B043)

One directed read per CSR word at t=reset+8 mm_clk cycles. Any RW word reads its defined power-on default.

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B023_uid_reset_value | Read 0x00 UID once after reset | Returns 0x52434D48 ("RCMH"); no runctl/upload activity | planned |
| B024_meta_reset_value | Read 0x01 META once after reset (selector=0) | Returns scoreboard VERSION constant; selector power-on default is 0 | planned |
| B025_control_reset_value | Read 0x02 CONTROL after reset | Returns 0x00000000 (both masks clear, W1P bits read 0) | planned |
| B026_status_reset_value | Read 0x03 STATUS after reset | recv_idle=1, host_idle=1, log_fifo_empty=1, dp_hr=0, ct_hr=0, recv_state_enc=0x00, host_state_enc=0x00, local_cmd_busy=0 | planned |
| B027_last_cmd_reset_value | Read 0x04 LAST_CMD after reset | Returns 0x00000000 (no command seen yet) | planned |
| B028_scratch_reset_value | Read 0x05 SCRATCH after reset | Returns 0x00000000 | planned |
| B029_run_number_reset_value | Read 0x06 RUN_NUMBER after reset | Returns 0x00000000 | planned |
| B030_reset_mask_reset_value | Read 0x07 RESET_MASK after reset | Returns 0x00000000 (no RESET / STOP_RESET issued) | planned |
| B031_fpga_address_reset_value | Read 0x08 FPGA_ADDRESS after reset | Returns 0x00000000; sticky valid bit [31]=0 | planned |
| B032_recv_ts_l_reset_value | Read 0x09 RECV_TS_L after reset | Returns 0x00000000 | planned |
| B033_recv_ts_h_reset_value | Read 0x0A RECV_TS_H after reset | Returns 0x00000000 | planned |
| B034_exec_ts_l_reset_value | Read 0x0B EXEC_TS_L after reset | Returns 0x00000000 | planned |
| B035_exec_ts_h_reset_value | Read 0x0C EXEC_TS_H after reset | Returns 0x00000000 | planned |
| B036_gts_l_reset_value | Read 0x0D GTS_L within 8 mm_clk of reset release | Returns gts[31:0] approximately equal to zero (small CDC-bounded value); read atomically latches [47:32] into GTS_H shadow | planned |
| B037_gts_h_reset_value | Read 0x0E GTS_H after B036's GTS_L read in same episode | Returns the [47:32] shadow captured by B036 (approximately zero) | planned |
| B038_rx_cmd_count_reset_value | Read 0x0F RX_CMD_COUNT after reset | Returns 0x00000000 | planned |
| B039_rx_err_count_reset_value | Read 0x10 RX_ERR_COUNT after reset | Returns 0x00000000 | planned |
| B040_log_status_reset_value | Read 0x11 LOG_STATUS after reset | Returns rdempty=1, rdfull=0, rdusedw=0 (bit pattern 0x00010000) | planned |
| B041_log_pop_reset_value | Read 0x12 LOG_POP after reset with empty FIFO | Returns 0x00000000; LOG_STATUS unchanged after the read | planned |
| B042_local_cmd_reset_value | Read 0x13 LOCAL_CMD after reset (no prior write) | Returns 0x00000000 | planned |
| B043_ack_symbols_reset_value | Read 0x14 ACK_SYMBOLS after reset | Returns 0x0000FDFE (RUN_START_ACK=0xFE at [7:0], RUN_END_ACK=0xFD at [15:8]) | planned |

### 6.2 RW write-then-read smoke for every RW word (B044-B058)

Directed write / read-back coverage for META, CONTROL, SCRATCH, LOCAL_CMD.

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B044_meta_page_0 | Write 0x00000000 to META, read META | Read returns VERSION payload | planned |
| B045_meta_page_1 | Write 0x00000001 to META, read META | Read returns DATE payload | planned |
| B046_meta_page_2 | Write 0x00000002 to META, read META | Read returns GIT short-hash payload | planned |
| B047_meta_page_3 | Write 0x00000003 to META, read META | Read returns INSTANCE_ID payload | planned |
| B048_control_mask_dp_only | Write 0x00000010 (rst_mask_dp=1), read CONTROL | Returns 0x00000010; bits 0/1 read 0 | planned |
| B049_control_mask_ct_only | Write 0x00000020 (rst_mask_ct=1), read CONTROL | Returns 0x00000020 | planned |
| B050_control_mask_both | Write 0x00000030, read CONTROL | Returns 0x00000030 | planned |
| B051_control_mask_none | Write 0x00000030 then 0x00000000, read CONTROL | Second read returns 0x00000000 | planned |
| B052_control_reserved_bits_ignored | Write 0xFFFFFFFF to CONTROL, read CONTROL | Read returns 0x00000030 (only bits [5:4] latch; bits 0/1 are W1P and self-clear; all other bits reserved RO0) | planned |
| B053_scratch_zero | Write 0x00000000 to SCRATCH, read | Returns 0x00000000 | planned |
| B054_scratch_ones | Write 0xFFFFFFFF to SCRATCH, read | Returns 0xFFFFFFFF | planned |
| B055_scratch_5a | Write 0x5A5A5A5A to SCRATCH, read | Returns 0x5A5A5A5A | planned |
| B056_scratch_a5 | Write 0xA5A5A5A5 to SCRATCH, read | Returns 0xA5A5A5A5 | planned |
| B057_local_cmd_readback_last | Write LOCAL_CMD=0x12000000, poll busy to 0, read LOCAL_CMD | Read returns 0x12000000 (per spec, LOCAL_CMD read returns last submitted word) | planned |
| B058_local_cmd_readback_after_two | Write LOCAL_CMD=0x11000000 then 0x32000000 (each after busy clears), read LOCAL_CMD | Read returns 0x32000000 (most recent submission) | planned |

### 6.3 Per-command synclink smoke with payload variations (B059-B073)

One test per command byte, plus payload corners for RUN_PREPARE, RESET, STOP_RESET, ADDRESS.

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B059_synclink_run_prepare_runnum_0 | Send 0x10 + run_number 0x00000000 | LAST_CMD[7:0]=0x10, RUN_NUMBER=0, log 4-word entry queued, upload ack with K30.7 (0xFE) and data[31:8]=24b run_number=0, bits[35:32]=0x1 k-flag, sop=eop=1 | planned |
| B060_synclink_run_prepare_runnum_1 | Send 0x10 + run_number 0x00000001 | RUN_NUMBER=1; upload ack run_number field = 24'h000001 | planned |
| B061_synclink_run_prepare_runnum_deadbeef | Send 0x10 + run_number 0xDEADBEEF | RUN_NUMBER=0xDEADBEEF; upload ack data[31:8]=24'hADBEEF (lower 24 bits of run_number) | planned |
| B062_synclink_run_sync | Send 0x11 (no payload) | runctl emits 0x11; LAST_CMD[7:0]=0x11; no upload ack; log entry payload word=0 | planned |
| B063_synclink_start_run | Send 0x12 | runctl emits 0x12; LAST_CMD=0x12; no upload; log queued | planned |
| B064_synclink_end_run | Send 0x13 | runctl emits 0x13; upload ack K29.7 (0xFD), payload bits[31:8]=0, bits[35:32]=0x1, sop=eop=1 | planned |
| B065_synclink_abort_run | Send 0x14 | runctl emits 0x14; no upload; log queued | planned |
| B066_synclink_reset_mask_00 | Send 0x30 + 16b assert mask 0x0000 | runctl emits 0x30; dp_hard_reset and ct_hard_reset both asserted; RESET_MASK[15:0]=0x0000 | planned |
| B067_synclink_reset_mask_ffff | Send 0x30 + mask 0xFFFF | RESET_MASK[15:0]=0xFFFF; dp/ct_hard_reset both asserted (RTL does not gate assertion by payload mask; only CONTROL.rst_mask_* gates) | planned |
| B068_synclink_reset_mask_0001 | Send 0x30 + mask 0x0001 | RESET_MASK[15:0]=0x0001; dp/ct_hard_reset asserted | planned |
| B069_synclink_reset_mask_aa55 | Send 0x30 + mask 0xAA55 | RESET_MASK[15:0]=0xAA55; dp/ct_hard_reset asserted | planned |
| B070_synclink_stop_reset_mask_ffff | Send 0x31 + 16b release mask 0xFFFF | RESET_MASK[31:16]=0xFFFF; dp/ct_hard_reset deasserted | planned |
| B071_synclink_enable | Send 0x32 | runctl emits 0x32; LAST_CMD[7:0]=0x32; log queued | planned |
| B072_synclink_disable | Send 0x33 | runctl emits 0x33; LAST_CMD[7:0]=0x33 | planned |
| B073_synclink_address_beef | Send 0x40 + 16b address 0xBEEF | FPGA_ADDRESS[15:0]=0xBEEF, [31]=1; LAST_CMD[31:16]=0xBEEF, [7:0]=0x40; runctl emits zero transactions for this command (ADDRESS is local-only); aso_runctl_data is NOT driven | planned |

### 6.4 LOCAL_CMD path smoke for every command class (B074-B083)

Mirror of 6.3 using the mm-side LOCAL_CMD injector. LOCAL_CMD word layout: [7:0]=cmd byte, [31:8]=payload MSB-first.

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B074_local_cmd_run_prepare | Write LOCAL_CMD=0x00000010 then poll busy (RUN_PREPARE with run_number=0 in payload field) | runctl emits 0x10; RUN_NUMBER reflects payload; upload ack K30.7 emitted; LAST_CMD[7:0]=0x10 | planned |
| B075_local_cmd_run_sync | Write LOCAL_CMD=0x00000011 | runctl emits 0x11; no upload; LAST_CMD=0x11 | planned |
| B076_local_cmd_start_run | Write LOCAL_CMD=0x00000012 | runctl emits 0x12; LAST_CMD=0x12 | planned |
| B077_local_cmd_end_run | Write LOCAL_CMD=0x00000013 | runctl emits 0x13; upload ack K29.7 emitted; LAST_CMD=0x13 | planned |
| B078_local_cmd_abort_run | Write LOCAL_CMD=0x00000014 | runctl emits 0x14; LAST_CMD=0x14 | planned |
| B079_local_cmd_reset | Write LOCAL_CMD=0x00000030 (RESET, mask=0x0000 in payload field) | runctl emits 0x30; dp/ct_hard_reset asserted; RESET_MASK[15:0]=0x0000 | planned |
| B080_local_cmd_stop_reset | Write LOCAL_CMD=0x00000031 | runctl emits 0x31; dp/ct_hard_reset deasserted; RESET_MASK[31:16]=0x0000 | planned |
| B081_local_cmd_enable | Write LOCAL_CMD=0x00000032 | runctl emits 0x32; LAST_CMD=0x32 | planned |
| B082_local_cmd_disable | Write LOCAL_CMD=0x00000033 | runctl emits 0x33; LAST_CMD=0x33 | planned |
| B083_local_cmd_address | Write LOCAL_CMD=0xBEEF0040 (ADDRESS, 16b addr=0xBEEF) | FPGA_ADDRESS[15:0]=0xBEEF, [31]=1; runctl emits zero transactions | planned |

### 6.5 Upload ack field-level directed checks (B084-B086)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B084_upload_ack_run_prepare_fields | Send synclink RUN_PREPARE with run_number=0xA5A5A5; check upload beat | Single beat: data[7:0]=0xFE (K30.7), data[31:8]=0xA5A5A5, data[35:32]=0x1 (k-flag), sop=1, eop=1 | planned |
| B085_upload_ack_end_run_fields | Send synclink END_RUN; check upload beat | Single beat: data[7:0]=0xFD (K29.7), data[31:8]=0x000000, data[35:32]=0x1, sop=1, eop=1 | planned |
| B086_upload_no_ack_for_other_cmds | Send each of 0x11,0x12,0x14,0x30,0x31,0x32,0x33,0x40 in sequence; check upload | Upload source emits zero beats across the entire sequence | planned |

### 6.6 Per-command log entry readback (B087-B089)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B087_log_entry_run_prepare | Send RUN_PREPARE + run_number=0x12345678; then pop 4 sub-words via LOG_POP | sw0=recv_ts[47:16]; sw1[31:16]=recv_ts[15:0], sw1[7:0]=0x10, sw1[15:8]=0; sw2=0x12345678; sw3=exec_ts[31:0]; LOG_STATUS.rdempty=1 after pops | planned |
| B088_log_entry_reset | Send RESET + mask=0xAA55; pop 4 sub-words | sw2={release_mask=0x0000, assert_mask=0xAA55} per DV_PLAN 3.6 (payload[31:0]=reset mask word); sw1[7:0]=0x30 | planned |
| B089_log_entry_address | Send ADDRESS + addr=0xBEEF; pop 4 sub-words | sw1[7:0]=0x40; sw2[31:0]=0x0000BEEF; LOG_STATUS empty after pops | planned |

### 6.7 GTS atomic snapshot smoke (B090-B091)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B090_gts_pair_read | Wait 4096 lvdspll cycles; read GTS_L then GTS_H; combine as 48b | 48b value non-zero, monotonically > 0; GTS_H read returns the shadow latched at the GTS_L edge, not the live upper bits | planned |
| B091_gts_repeat_pair | B090 then wait 4096 lvdspll cycles and read GTS_L/GTS_H again | Second 48b value strictly greater than first; each pair internally consistent | planned |

### 6.8 STATUS field directed encoding (B092-B093)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B092_status_recv_payload_state | Drive synclink RUN_PREPARE command byte then withhold the next valid byte for 32 lvdspll cycles; read STATUS during stall | STATUS[15:8] recv_state_enc = 0x01 (RX_PAYLOAD); recv_idle=0 | planned |
| B093_status_host_logging_state | Stall runctl sink ready=0; send RUN_SYNC; once recv has posted to host, read STATUS | STATUS[23:16] host_state_enc matches the "LOGGING/POSTING" encoding (0x02 per DV_PLAN host FSM table); host_idle=0 | planned |

### 6.9 Counter smoke (B094-B095)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B094_rx_cmd_count_eight | Send 8 back-to-back RUN_SYNC (0x11) bytes over synclink | RX_CMD_COUNT increments by exactly 8; RX_ERR_COUNT unchanged | planned |
| B095_rx_err_count_four | Inject 4 synclink bytes with error[1]=1 (parity) | RX_ERR_COUNT increments by exactly 4; RX_CMD_COUNT unchanged; no runctl/upload traffic | planned |

### 6.10 W1P pulse behavior and reserved-bit masking (B096-B098)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B096_control_soft_reset_w1p | Write CONTROL=0x00000001; read CONTROL immediately after waitrequest drops | Read returns CONTROL[0]=0; the pulse internally triggered soft_reset CDC + CSR_LOG_FLUSH drain; waitrequest was held high for the triggering write until mm-side log FIFO rdempty=1; GTS counter and saturating counters NOT cleared | planned |
| B097_control_log_flush_w1p | Queue 2 commands (8 log sub-words), then write CONTROL=0x00000002; read CONTROL | Read returns CONTROL[1]=0; CSR_LOG_FLUSH drained mm-side of the log FIFO before waitrequest dropped; LOG_STATUS.rdempty=1 after; lvdspll-side FSMs NOT reset | planned |
| B098_control_reserved_bits_only_4_latch | Write CONTROL=0xFFFFFFCC (bits 0/1/4/5 = 0, all other bits = 1); read CONTROL | Read returns 0x00000000: reserved bits are RO0 and ignored on write | planned |

### 6.11 Miscellaneous frozen-decision smoke (B099-B100)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| B099_waitrequest_idle_and_mm_reset | (a) With bus idle, sample waitrequest for 64 mm_clk cycles. (b) Assert mm_reset=1 and issue an AVMM read to 0x03 STATUS while held in reset | (a) waitrequest stays 0 across the idle window. (b) During mm_reset: waitrequest=1, readdata=0, no CSR shadow changes, no runctl/upload activity | planned |
| B100_fpga_address_valid_sticky | Send ADDRESS cmd with addr=0x1234; then send RUN_SYNC, START_RUN, END_RUN in sequence; read FPGA_ADDRESS after each | FPGA_ADDRESS[15:0]=0x1234 and [31]=1 remain stable across all three subsequent non-ADDRESS commands; unknown command byte 0x77 injected after also does not disturb (silently dropped: no fanout, no log, no RX_CMD_COUNT / RX_ERR_COUNT change) | planned |

### 6.12 Section note

Total B-case count after this expansion: **100** (B001..B100). Detailed long-form specifications cover B001..B022 (sections 1..5); compact table entries cover B023..B100 (section 6). Every frozen RTL decision listed in the plan preamble is covered by at least one directed case:

- LOCAL_CMD waitrequest stall while busy: covered by B057/B058 (readback after busy), and stall semantics deferred to DV_EDGE E013 for the back-to-back contention case.
- Log FIFO drop-new policy with `log_drop_count` saturating backdoor counter: **intentionally deferred** to DV_EDGE (near-full + drop scenario) because the counter is not exposed via CSR; the backdoor probe check belongs to a stress test, not a bring-up smoke.
- CONTROL.soft_reset W1P + CSR_LOG_FLUSH + CDC pulse into lvdspll_clk: B096.
- CONTROL.log_flush W1P + CSR_LOG_FLUSH (without lvds reset): B097.
- Unknown command byte silently dropped (no fanout, no log, no counter bump): B100.
- CSR access during mm_reset: B099(b).
- Reserved/RO word writes complete in 1 cycle with no side effects: B002 (UID) plus B052/B098 (CONTROL reserved bits).
- `RX_CMD_COUNT` / `RX_ERR_COUNT` / `log_drop_count` saturate at 0xFFFFFFFF: saturation itself is an edge case (requires 2^32 increments) and is **intentionally deferred** to DV_EDGE; B094/B095 cover the non-saturating increment path only.
- `LOG_POP` on empty returns 0: B041.
- `GTS_L` atomic snapshot latches [47:32] into the GTS_H shadow: B036/B037 and B090/B091.
- `aso_runctl_data` NOT driven for `CMD_ADDRESS`: B073, B083, B089.
- `rc_pkt_upload` ack for RUN_PREPARE (K30.7, 24b run_number in [31:8]) and END_RUN (K29.7 zero payload), bits [35:32]=4'b0001, sop=eop=1: B084, B085, B086.
- LOCAL_CMD word layout [7:0]=cmd, [31:8]=payload MSB-first: B074..B083.
- recv FSM priority (local_cmd pending > synclink byte) inside RECV_IDLE: smoke covered implicitly by B074..B083 running in quiescent synclink; the priority contention case is deferred to DV_CROSS X003/X011.
- `dp_hard_reset` / `ct_hard_reset` asserted on `pipe_r2h_done` for `CMD_RESET` / `CMD_STOP_RESET` gated by `CONTROL.rst_mask_dp` / `rst_mask_ct`: non-gated assertion path in B066..B070 and B079/B080; the mask-gated suppression path belongs to the 4x2 truth-table sweep in DV_EDGE E007..E009 and DV_CROSS X004 (already catalogued) and is **intentionally deferred** from DV_BASIC.

Gaps intentionally left for DV_EDGE / DV_CROSS / DV_ERROR:

- 32-bit counter saturation (RX_CMD_COUNT, RX_ERR_COUNT, log_drop_count) — DV_EDGE.
- Log FIFO near-full + drop-new with backdoor `log_drop_count` probe — DV_EDGE.
- LOCAL_CMD back-to-back stall via waitrequest (CSR_LOCAL_WAIT state) — DV_EDGE E013.
- recv FSM priority (local_cmd vs synclink byte contention in RECV_IDLE) — DV_CROSS X003/X011.
- rst_mask_{dp,ct} gated suppression truth table — DV_EDGE E007..E009 + DV_CROSS X004.
- Synclink parity / decode / loss-sync error recovery — DV_ERROR R001..R003, R016, R017.
- mid-command reset and soft-reset-during-traffic — DV_ERROR R007..R010.

---

## 7. Plan drift notes

The following items were observed while expanding section 6.1 of DV_PLAN.md into this document. None of these change test IDs, test count, or the stimulus/expected intent defined in the plan — they are flagged here so the plan can be updated in a future revision.

- **B004 scratch pattern vs. coverage bin set.** The plan's B004 row nominally writes `0xA5A5A5A5`, but the `scratch_pattern` coverage group in section 5.1 lists only `{0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555}`. `0xA5A5A5A5` does not match any bin. B004 therefore also writes `0xDEADBEEF` and `0xCAFE_BABE` per the user instructions and still hits only `csr_writeread_pair[0x05]`. A dedicated scratch-pattern test must appear in DV_CROSS (X015 already exists) to hit all four `scratch_pattern` bins.
- **B005 soft_reset / log_flush W1P bits.** The plan does not include a dedicated basic test that exercises `control_writeable_bits[bit0]` and `control_writeable_bits[bit1]`. Those two bins are covered by DV_EDGE E014 (soft_reset) and E015 (log_flush). B005 intentionally does not pulse them, matching the plan text ("Set CONTROL.rst_mask_dp / rst_mask_ct, read back").
- **B007 log_flush semantics.** The plan's CONTROL table calls the soft_reset pulse "clears recv FSM, host FSM, snapshot record, log FIFO read pointer". The instruction given for authoring this file says soft_reset "clears log FIFO" whereas the plan says it clears the log FIFO *read pointer*. B007 and B017 rely on the plan wording (entries remain in the FIFO until popped); the soft-reset behavior is tested in E014 and the exact semantic must be pinned down in DV_HARNESS scoreboard implementation.
- **B012/B013 runctl fanout for 0x30/0x31.** Section 3.7 of the plan lists CMD_RESET and CMD_STOP_RESET as "Drives dp/ct_hard_reset gated by CONTROL mask" and does not explicitly say the byte is also fanned out on runctl. B012/B013 assume one runctl transaction for each, consistent with the legacy `runctl_mgmt_host_v24.vhd` datapath. If RTL ends up not fanning these out on runctl, B012/B013 must relax the "one runctl transaction" check and the plan text in section 3.7 should be clarified.
- **B018 RX_CMD_COUNT accounting for ADDRESS.** The plan does not state whether `0x40` (which does not fan out on runctl) increments RX_CMD_COUNT. This test assumes yes (it is an "accepted command"), giving the total of 8. If the RTL spec is tightened to count only runctl-fanout commands, B018 must be updated to expect `baseline + 7` and the plan section 3 text should be updated accordingly.
- **B020 GTS live-counter source.** The plan says the live GTS "is reset only by lvdspll_reset". The user instructions echo this. B020 enforces monotonic behavior across two samples and compares against the scoreboard-shadowed live counter with a bounded CDC uncertainty window; the exact window width is deferred to DV_HARNESS.
