# runctl_mgmt_host DV -- Error, Reset, and Recovery Cases

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Bucket:** R (recovery / error injection)
**ID Range:** R001-R999
**Implemented ordinals this file:** R001-R017 (matches DV_PLAN section 6.4)
**Method:** All directed (D)
**Author:** Yifeng Wang (yifenwan@phys.ethz.ch)
**Date:** 2026-04-13
**Status:** Planning. No tests implemented. Some cases flagged "needs RTL lock" because the RTL has not been written and the DV must pin the behavior at authoring time.

This document expands every R-ID in DV_PLAN.md section 6.4 into a full per-test schema. Every error test verifies **both** detection (counter / status flag) and **recovery** (DUT returns to a usable state within a stated cycle budget). No test may hang the DUT.

---

## 0. Conventions

### 0.1 Recovery criteria (applied to every R-case)

A case passes only if all of the following hold:

1. **No hang.** A 50000-cycle env-level watchdog fires before any expected quiescence point is missed.
2. **Detection.** The expected status flag or counter reaches the expected post-fault value (scoreboard-shadowed).
3. **Recovery.** recv_state returns to IDLE and host_state returns to IDLE within the budget listed per case; STATUS.recv_idle=1 and STATUS.host_idle=1 are observable on the CSR side afterwards.
4. **No leakage.** A post-recovery smoke sequence (1x RUN_SYNC through synclink) is processed normally by the scoreboard.
5. **Counter correctness.** RX_ERR_COUNT or RX_CMD_COUNT post-value equals pre-value + number of faults/valid commands injected (with saturation respected).

### 0.2 Error encoding on the synclink AVST sink

Per DV_PLAN section 2:

| error[2] | error[1] | error[0] | Meaning |
|----------|----------|----------|---------|
| 0        | 0        | 0        | clean byte |
| 0        | 0        | 1        | decode error |
| 0        | 1        | 0        | parity error |
| 1        | x        | x        | loss of sync |

Combinations with multiple bits set are defined as "loss_sync dominates", then "parity dominates decode", but the error counter increments once per byte regardless of which bits are set. This policy is asserted by `sva_synclink` and checked in R016.

### 0.3 recv_state encoding (as seen on STATUS[15:8])

LOG_ERROR is the FSM's sink state for flagged bytes. It must exist in RTL; see "Plan drift notes" if the final RTL uses a different label.

| enc | state |
|-----|-------|
| 0x00 | IDLE |
| 0x01 | RX_PAYLOAD |
| 0x02 | POSTING |
| 0x03 | LOG_WR |
| 0x04 | LOG_ERROR |

Other encodings are reserved and must decode as "unknown" by the scoreboard.

### 0.4 Coverage bin references

Bins referenced by R-cases live in `runctl_mgmt_cov` (DV_PLAN section 5). Names quoted here are:

- `cov_cmd.cmd_byte_unknown` -- one bin for any byte not in the defined set
- `cov_cmd.cmd_byte_synclink[...]` -- per-byte synclink bins
- New counter-based bins introduced by this error plan (added to `runctl_mgmt_cov` and listed in section 5 of this file).

---

## 1. synclink Link Errors (R001-R003, R016, R017) -- 5 cases

The synclink AVST sink is the only path the DUT can use to learn that an upstream 5G link byte was bad. On any error[2:0] != 0 the DUT must:

- increment RX_ERR_COUNT (saturating at 32-bit max),
- drop the byte (no fanout, no log entry, no upload ack),
- transition recv_state from its current state to LOG_ERROR and from LOG_ERROR back to IDLE within 4 lvdspll_clk cycles,
- leave RX_CMD_COUNT untouched.

Recovery budget for all section 1 cases: **32 lvdspll_clk cycles** from the last error byte to STATUS.recv_idle=1.

### R001_synclink_parity_error

| Field | Value |
|-------|-------|
| Category | synclink link error / soft error |
| Goal | Single parity error while idle; DUT counts, drops, recovers. |
| Setup | Full reset. CSR shadow reset. runctl sink ready=1. upload sink ready=1. RX_ERR_COUNT pre=0. RX_CMD_COUNT pre=0. |
| Injection | 1. Cycle C0: drive synclink valid=1, data=0x10, error={0,1,0}. 2. Cycle C1: drive valid=0 for 8 cycles. |
| Expected recovery | 1. C0+1: recv_state -> LOG_ERROR. 2. C0+2..C0+4: recv_state -> IDLE. 3. runctl source: 0 beats. 4. upload source: 0 beats. 5. log FIFO: unchanged (empty). 6. CSR RX_ERR_COUNT read = 1. |
| Coverage bins | `cov_err.err_class[parity]++`, `cov_err.err_state_entry[IDLE]++`, `cov_err.recovery_latency_bin[<=4]++`. |
| Pass criteria | (a) no hang within 32 cycles of C0, (b) STATUS.recv_idle=1 sampled at C0+8, (c) RX_ERR_COUNT reads exactly 1, (d) no runctl beats, no upload beats, no log entries. |
| Status | planned |

### R002_synclink_decode_error

| Field | Value |
|-------|-------|
| Category | synclink link error / soft error |
| Goal | Same as R001 but with decode error. |
| Setup | Identical to R001. |
| Injection | 1. C0: synclink valid=1, data=0x11, error={0,0,1}. 2. C1..C8: valid=0. |
| Expected recovery | Same as R001, substituting parity for decode. |
| Coverage bins | `cov_err.err_class[decode]++`, `cov_err.err_state_entry[IDLE]++`. |
| Pass criteria | Same as R001 with RX_ERR_COUNT=1. |
| Status | planned |

### R003_synclink_loss_sync

| Field | Value |
|-------|-------|
| Category | synclink link error / soft error |
| Goal | Loss-of-sync mid-command aborts the in-flight command cleanly. |
| Setup | Full reset. RX_ERR_COUNT pre=0. |
| Injection | 1. C0: synclink valid=1, data=0x10 (RUN_PREPARE), error=0. 2. C1..C2: synclink valid=1, payload bytes 0 and 1, error=0. (recv_state is RX_PAYLOAD with 2 of 4 payload bytes captured.) 3. C3: synclink valid=1, data=0xAA, error={1,0,0} (loss_sync dominates). 4. C4..C32: valid=0. |
| Expected recovery | 1. C0: recv_state -> RX_PAYLOAD. 2. C3+1: recv_state -> LOG_ERROR. 3. C3+2..C3+4: recv_state -> IDLE. 4. Partial payload discarded: no LAST_CMD update, no RUN_NUMBER update, no log entry, no upload ack. 5. runctl source: 0 beats. |
| Coverage bins | `cov_err.err_class[loss_sync]++`, `cov_err.err_state_entry[RX_PAYLOAD]++`, `cov_err.truncated_cmd[RUN_PREPARE]++`. |
| Pass criteria | (a) no hang, (b) STATUS.recv_idle=1 at C3+8, (c) RX_ERR_COUNT=1, (d) LAST_CMD unchanged, RUN_NUMBER unchanged, log FIFO still empty, (e) RX_CMD_COUNT unchanged. |
| Status | planned |

### R016_simultaneous_cmd_and_err

| Field | Value |
|-------|-------|
| Category | synclink link error / mixed stream |
| Goal | Interleaved valid bytes and errored bytes must be classified independently. Counters must not cross-contaminate. |
| Setup | Full reset. RX_ERR_COUNT pre=0. RX_CMD_COUNT pre=0. runctl sink ready=1. |
| Injection | 1. Stream 32 bytes at 1 byte / lvds cycle. Even byte indices: valid RUN_SYNC (0x11) with error=0. Odd byte indices: 0x00 with error={0,1,0} (parity). 2. 16 valid RUN_SYNCs and 16 parity errors, alternating. |
| Expected recovery | 1. For each valid byte: recv_state traverses IDLE -> POSTING -> LOG_WR -> IDLE; host FSM emits 0x11 on runctl. 2. For each errored byte: recv_state traverses current -> LOG_ERROR -> IDLE. 3. After the 32-byte stream: RX_CMD_COUNT=16, RX_ERR_COUNT=16. 4. Log FIFO holds 16 entries for the 16 valid RUN_SYNCs. |
| Coverage bins | `cov_err.err_class[parity]+=16`, `cov_err.mixed_stream_hit++`, `cov_cmd.cmd_byte_synclink[0x11]++` hit 16 times. |
| Pass criteria | (a) no hang, (b) RX_CMD_COUNT=16 and RX_ERR_COUNT=16 (exact, not saturated), (c) all 16 runctl fanout beats observed, (d) 16 log entries, (e) no upload beats, (f) recv_state returns to IDLE within 32 cycles of last byte. |
| Status | planned |

### R017_recovery_after_loss_sync

| Field | Value |
|-------|-------|
| Category | synclink link error / recovery smoke |
| Goal | After R003, the DUT processes a clean command sequence with no residual state. |
| Setup | Execute R003 injection first. RX_ERR_COUNT=1, no log entries, recv/host idle. |
| Injection | 1. After recovery to IDLE, send a clean RUN_PREPARE with run_number=0xA5A50000 (1 byte + 4 payload bytes). 2. Follow with CMD_END_RUN (1 byte). 3. Follow with CMD_ABORT_RUN (1 byte). |
| Expected recovery | 1. RUN_PREPARE: LAST_CMD=0x10, RUN_NUMBER=0xA5A50000, log entry queued, upload ack with K30.7. 2. END_RUN: LAST_CMD=0x13, runctl emits 0x13, upload ack with K29.7. 3. ABORT_RUN: LAST_CMD=0x14, runctl emits 0x14. |
| Coverage bins | `cov_cmd.cmd_byte_synclink[0x10,0x13,0x14]` each +1, `cov_cmd.upload_ack_class[K30.7,K29.7]` each +1. |
| Pass criteria | (a) no hang, (b) all three commands scoreboard-matched, (c) RX_ERR_COUNT still 1 (unchanged from R003), (d) RX_CMD_COUNT = 3, (e) no additional LOG_ERROR transitions observed. |
| Status | planned |

---

## 2. Malformed Commands (R004) -- 1 case

### R004_unknown_cmd_byte

| Field | Value |
|-------|-------|
| Category | malformed command / parser hardening |
| Goal | An unknown command byte (not in {0x10..0x14, 0x30..0x33, 0x40}) must be **accepted at the recv FSM** (no error flag), **treated as payload-len=0**, not fanned out on runctl, not logged, not upload-ack'd, and must not block subsequent traffic. |
| Setup | Full reset. runctl and upload sinks ready=1. RX_ERR_COUNT pre=0. RX_CMD_COUNT pre=0. |
| Injection | 1. C0: synclink valid=1, data=0x77 (unknown), error=0. 2. C1..C8: valid=0. 3. C9: synclink valid=1, data=0x10 (RUN_PREPARE), error=0. 4. C10..C13: 4 payload bytes for run_number=0x00000001. 5. C14..C24: valid=0. |
| Expected recovery | 1. C0+1: recv_state transitions through a "decode unknown" path. Either (a) the byte is silently dropped and recv_state returns to IDLE in <= 4 cycles, or (b) the byte is counted in RX_CMD_COUNT with payload-len=0 and no fanout. 2. No runctl beat, no upload beat, no log entry for the 0x77 byte. 3. The subsequent RUN_PREPARE is fully processed: LAST_CMD=0x10, RUN_NUMBER=0x00000001, one log entry, one upload K30.7 ack. |
| Coverage bins | `cov_cmd.cmd_byte_unknown++` (new, added by this plan). |
| Pass criteria | (a) no hang, (b) scoreboard observes the post-fault RUN_PREPARE exactly once, (c) RX_ERR_COUNT=0 (unknown byte is NOT a link error), (d) RX_CMD_COUNT matches whichever lock the RTL gives -- see PROPOSAL below. |
| PROPOSAL | **needs RTL lock.** Candidate (A): drop the unknown byte, RX_CMD_COUNT unchanged (=1 after the RUN_PREPARE). Candidate (B): accept it as zero-payload "nop", RX_CMD_COUNT=2. The current DV must lock one of these when RTL is written. Until then the scoreboard allows either, but the `cov_cmd.cmd_byte_unknown` bin must be hit. |
| Status | planned |

---

## 3. Payload Truncation (R005, R006) -- 2 cases

### R005_truncated_run_prepare

| Field | Value |
|-------|-------|
| Category | payload truncation / parser resync |
| Goal | A RUN_PREPARE whose 32-bit payload is interrupted by a stream pause must not corrupt the next command. Two sub-scenarios: (a) loss_sync terminates the truncated command, (b) the payload eventually completes after a long stream pause. |
| Setup | Full reset. RX_CMD_COUNT pre=0. RX_ERR_COUNT pre=0. |
| Injection (sub-case A, loss_sync terminates) | 1. C0: valid=1, data=0x10, error=0. 2. C1..C2: valid=1, payload bytes 0 and 1, error=0 (recv in RX_PAYLOAD with 2 of 4 bytes). 3. C3..C50: valid=0 (stream pause). 4. C51: valid=1, data=0xFF, error={1,0,0} (loss_sync). 5. C52..C80: valid=0. 6. C81..C85: valid=1, send clean RUN_SYNC byte (0x11) followed by clean END_RUN byte (0x13). |
| Injection (sub-case B, stream resumes cleanly) | 1. C0: valid=1, data=0x10, error=0. 2. C1..C2: valid=1, payload bytes 0 and 1, error=0. 3. C3..C200: valid=0. 4. C201..C202: valid=1, payload bytes 2 and 3, error=0 (stream resumes, completing the 4-byte payload). 5. C203..C210: valid=0. |
| Expected recovery (A) | 1. recv_state enters RX_PAYLOAD at C0+1, holds through the pause, enters LOG_ERROR on loss_sync, returns to IDLE by C51+4. 2. No LAST_CMD update, no RUN_NUMBER update, no log entry, no upload ack for the truncated RUN_PREPARE. 3. RX_ERR_COUNT=1. 4. RUN_SYNC and END_RUN both processed normally. 5. RX_CMD_COUNT=2 (only the two clean commands). |
| Expected recovery (B) | 1. recv_state holds in RX_PAYLOAD during the pause with no byte loss (AVST sink has no timeout). 2. At C202 the RUN_PREPARE completes normally. RX_CMD_COUNT=1. One log entry. One upload K30.7 ack. RX_ERR_COUNT=0. |
| Coverage bins | `cov_err.truncated_cmd[RUN_PREPARE]++`, `cov_err.resume_after_pause_ok++` (B), `cov_err.loss_sync_during_pause++` (A). |
| Pass criteria | Both sub-cases: (a) no hang, (b) scoreboard observes exactly the expected post-sequence commands, (c) recv_state returns to IDLE by the stated cycle, (d) RX_ERR_COUNT exact. |
| PROPOSAL | **needs RTL lock.** Current DV_PLAN assumes "no timeout on RX_PAYLOAD" -- the FSM sits in RX_PAYLOAD indefinitely waiting for the next valid byte. If the RTL adds a payload-watchdog, sub-case B must be updated to check the watchdog-driven abort instead. |
| Status | planned |

### R006_truncated_reset

| Field | Value |
|-------|-------|
| Category | payload truncation / parser resync |
| Goal | CMD_RESET (16-bit mask payload) truncated mid-payload by loss_sync. Same properties as R005. |
| Setup | Full reset. CONTROL masks both 0. |
| Injection | 1. C0: valid=1, data=0x30, error=0. 2. C1: valid=1, payload byte 0 (low mask byte), error=0. 3. C2: valid=1, data=0x55, error={1,0,0} (loss_sync during second mask byte). 4. C3..C16: valid=0. 5. C17: valid=1, data=0x30, error=0. 6. C18..C19: valid=1, payload bytes 0xFF and 0xFF, error=0 (clean retry). |
| Expected recovery | 1. First RESET: recv_state -> RX_PAYLOAD -> LOG_ERROR -> IDLE. dp_hard_reset and ct_hard_reset are NOT asserted. RESET_MASK[15:0] unchanged. 2. RX_ERR_COUNT=1. 3. Second RESET processes normally: RESET_MASK[15:0]=0xFFFF, dp_hard_reset=1, ct_hard_reset=1 (masks both 0). |
| Coverage bins | `cov_err.truncated_cmd[RESET]++`, `cov_err.loss_sync_during_pause++`. |
| Pass criteria | (a) no hang, (b) RX_ERR_COUNT=1, (c) hard_reset outputs match only the retry, (d) RX_CMD_COUNT=1 (only the retry). |
| Status | planned |

---

## 4. CSR Violations (R011, R014, R015) -- 3 cases

### R011_local_cmd_during_busy

| Field | Value |
|-------|-------|
| Category | CSR misuse / local_cmd contention |
| Goal | Second LOCAL_CMD write while STATUS.local_cmd_busy=1 must not corrupt the first write or hang the AVMM. |
| Setup | Full reset. recv idle. runctl sink held ready=0 so LOCAL_CMD will dwell in the toggle-handshake longer. |
| Injection | 1. AVMM write LOCAL_CMD = 0x12000000 (START_RUN, no payload) at T0. 2. Read STATUS immediately, confirm local_cmd_busy=1. 3. AVMM write LOCAL_CMD = 0x14000000 (ABORT_RUN) at T0+4 mm_clk (still busy). 4. Release runctl sink ready=1 at T0+64. 5. Poll STATUS until local_cmd_busy=0. |
| Expected recovery | 1. First LOCAL_CMD crosses mm -> lvds via toggle, recv FSM accepts 0x12, host emits 0x12 on runctl after ready. 2. Second LOCAL_CMD is rejected per PROPOSAL below. 3. local_cmd_busy clears after first command retires. 4. RX_CMD_COUNT increments per accepted writes (1 or 2 depending on lock). |
| PROPOSAL | **needs RTL lock.** Candidates: (A) second write completes its AVMM phase cleanly but the data is dropped; local_cmd_busy stays high; only one runctl fanout observed. (B) second write blocks on waitrequest until the first retires, then accepts and fanouts 0x14. (C) AVMM returns immediate response but sets a sticky "local_cmd_dropped" error flag visible in STATUS (not currently in the CSR map). The DV will lock one of (A)/(B)/(C) when RTL lands. Today the scoreboard asserts (a) no AVMM hang and (b) at least one runctl fanout, and records actual observed behavior to drive the lock decision. |
| Coverage bins | `cov_err.local_cmd_busy_write++`. |
| Pass criteria | (a) no AVMM hang: both writes complete their waitrequest within 64 mm_clk, (b) no runctl deadlock: first LOCAL_CMD eventually fanouts, (c) scoreboard does not report a torn command (no half-0x12/half-0x14 byte on runctl), (d) local_cmd_busy eventually returns to 0. |
| Status | planned |

### R014_log_fifo_full_overflow

| Field | Value |
|-------|-------|
| Category | CSR / log FIFO fault path |
| Goal | Pushing more log entries than the FIFO can hold must saturate cleanly, not corrupt existing entries, not hang the recv FSM. Also verify LOG_POP on empty returns 0. |
| Setup | Full reset. Establish FIFO depth via LOG_STATUS.rdusedw width (10-bit per DV_PLAN section 3). Depth D = 1024 sub-words = 256 log entries (4 sub-words per entry). |
| Injection | 1. Stream D+16 = 272 clean RUN_SYNC (0x11) commands on synclink. 2. Without popping, read LOG_STATUS. 3. Issue LOG_POP 1024 times, record each return value. 4. After draining, issue 1 extra LOG_POP on empty FIFO, record return. |
| Expected recovery | 1. LOG_STATUS.rdfull=1 observed at some point during the push stream. 2. After 272 commands: LOG_STATUS.rdusedw=1024 (max), rdfull=1. 3. Popping 1024 sub-words yields the **first 256 committed entries** (drop-new policy) OR the **last 256 committed entries** (drop-old policy) -- see PROPOSAL. 4. The 1025th pop returns 0x00000000. 5. rdempty=1 after drain. 6. recv_state returns to IDLE after the last synclink byte. |
| PROPOSAL | **needs RTL lock.** The Altera `dcfifo_mixed_widths` configured with full=1 will either block writes (write side stalls) or drop writes (writes silently discarded, oldest entries preserved). Legacy `runctl_mgmt_host_v24.vhd` uses behavior X -- confirm from legacy, then lock. Scoreboard must pin the policy once decided. |
| Coverage bins | `cov_err.log_fifo_full++`, `cov_err.log_pop_empty++`, `cov_err.log_fifo_saturate_policy[<X>]++`. |
| Pass criteria | (a) no hang: all 272 commands enter recv FSM without stalling beyond the 256 sub-word-fill time, (b) LOG_STATUS.rdfull=1 sampled, (c) empty-pop returns 0, (d) scoreboard matches the locked saturation policy exactly. |
| Status | planned |

### R015_csr_addr_oob

| Field | Value |
|-------|-------|
| Category | CSR address fault |
| Goal | CSR accesses to out-of-range / reserved word addresses (0x15..0x1F) must not hang the Avalon-MM slave, must not produce side effects, and reads must return 0. |
| Setup | Full reset. AVMM master available. |
| Injection | 1. For each addr in {0x15, 0x16, 0x18, 0x1C, 0x1F}: (a) AVMM read, capture readdata; (b) AVMM write 0xDEADBEEF, check waitrequest releases within 4 mm_clk. 2. After the sweep, read SCRATCH (0x05) and LAST_CMD (0x04) to verify they are untouched. 3. Write 0xBEEFCAFE to SCRATCH (0x05) and read back to verify CSR is still alive. |
| Expected recovery | 1. Each OOB read returns 0x00000000. 2. Each OOB write has no effect. 3. SCRATCH round-trip works post-sweep. 4. No STATUS bit changes from the OOB accesses. |
| PROPOSAL | **needs RTL lock.** DV_PLAN section 2 says "no waitrequest" on the CSR slave. This is a strong commitment -- if the RTL uses a 1-cycle waitrequest for reads, this case adjusts to "waitrequest releases within 1 cycle" instead. Lock when RTL lands. |
| Coverage bins | `cov_err.csr_oob_read++` hit 5 times, `cov_err.csr_oob_write++` hit 5 times. |
| Pass criteria | (a) no AVMM hang: every OOB access completes within 4 mm_clk, (b) all OOB reads return 0, (c) SCRATCH round-trip matches, (d) no change to RX_CMD_COUNT, RX_ERR_COUNT, LAST_CMD, STATUS, FPGA_ADDRESS. |
| Status | planned |

---

## 5. Reset Interactions (R007, R008, R009, R010) -- 4 cases

### R007_mid_cmd_lvdspll_reset

| Field | Value |
|-------|-------|
| Category | reset interaction / lvdspll domain |
| Goal | lvdspll_reset asserted mid-payload must clear all recv/host/upload state and produce no partial outputs. |
| Setup | Full reset (both domains). Then send: (C0) RUN_PREPARE byte, (C1..C2) 2 of 4 payload bytes. recv_state is RX_PAYLOAD. |
| Injection | 1. C3: assert lvdspll_reset for 8 lvdspll_clk cycles. 2. C11: deassert. 3. C12..C19: synclink valid=0. 4. C20: send clean RUN_SYNC. |
| Expected recovery | 1. During lvdspll_reset: recv_state, host_state forced to IDLE; runctl source ready/valid both 0; upload source ready/valid both 0; dp_hard_reset, ct_hard_reset de-asserted (unless CONTROL masks them). 2. After lvdspll_reset deassert: recv FSM ready for a new byte. 3. C20 RUN_SYNC processes normally. 4. Log FIFO: the truncated RUN_PREPARE produces NO entry. The post-reset RUN_SYNC produces exactly one entry. 5. RX_CMD_COUNT=1, RX_ERR_COUNT=0 (loss_sync not injected). |
| Coverage bins | `cov_err.mid_cmd_reset[lvdspll]++`, `cov_err.truncated_cmd[RUN_PREPARE]++`. |
| Pass criteria | (a) no hang, (b) no runctl or upload beats from the truncated command, (c) post-reset RUN_SYNC scoreboard-matched, (d) STATUS.recv_idle=1 within 8 lvdspll_clk of deassert. |
| PROPOSAL | **needs RTL lock.** The CSR mm-domain shadows of CMD/PAYLOAD (LAST_CMD, RUN_NUMBER, etc.) are owned by mm_clk. lvdspll_reset only must NOT reset them. Candidate (A): CSR shadows survive lvdspll_reset and retain their last-valid values. Candidate (B): CSR shadows clear because the capture-toggle CDC signal is held low during lvds reset. DV locks when RTL lands. |
| Status | planned |

### R008_mid_cmd_mm_reset

| Field | Value |
|-------|-------|
| Category | reset interaction / mm domain |
| Goal | mm_reset asserted mid-payload must clear the CSR block to defaults while the lvdspll datapath continues running. A CSR waitrequest cycle must not deadlock if mm_reset arrives during it. |
| Setup | Send RUN_PREPARE byte + 2 payload bytes on synclink. recv_state=RX_PAYLOAD. Pre-populate SCRATCH=0xCAFEBABE. |
| Injection | 1. AVMM master issues read of RX_CMD_COUNT at T0. 2. Assert mm_reset at T0+0 (during the read's waitrequest or response phase, per PROPOSAL below). 3. Deassert mm_reset at T0+8 mm_clk. 4. T0+16: AVMM read RX_CMD_COUNT and SCRATCH. 5. On lvdspll side: send the remaining 2 payload bytes. |
| Expected recovery | 1. mm_reset does NOT reset lvdspll_clk FSM: recv_state continues, the 2 trailing payload bytes complete the RUN_PREPARE. 2. CSR shadows reset: RX_CMD_COUNT=0 after mm_reset, SCRATCH=0. 3. LAST_CMD after the lvdspll-side completion: depends on whether the scoreboard observes the recv FSM's POSTING via the mm-side capture toggle happening after mm_reset deassert. 4. AVMM is alive after mm_reset. |
| PROPOSAL | **needs RTL lock.** CSR waitrequest during mm_reset: Candidate (A) the read completes with 0; Candidate (B) readdatavalid never fires for the pre-reset read and the next read after reset succeeds. Candidate (B) is preferred because it mirrors standard synchronous slaves. |
| Coverage bins | `cov_err.mid_cmd_reset[mm]++`, `cov_err.csr_access_during_reset++`, `cov_err.scratch_reset_by_mm++`. |
| Pass criteria | (a) no AVMM hang: AVMM master watchdog 16 mm_clk from mm_reset deassert, (b) SCRATCH=0 after mm_reset (CSR shadow cleared), (c) lvdspll datapath delivered the remaining payload bytes without stalling, (d) RX_CMD_COUNT after a full post-reset RUN_PREPARE = 1. |
| Status | planned |

### R009_soft_reset_during_cmd

| Field | Value |
|-------|-------|
| Category | reset interaction / CONTROL.soft_reset |
| Goal | Pulse CONTROL.soft_reset (W1P) mid-command. All FSMs must go to IDLE, partial command discarded, no spurious outputs. This applies to recv in any state (IDLE, RX_PAYLOAD, POSTING, LOG_WR, LOG_ERROR). |
| Setup | 5 sub-cases, one per recv_state value. Pre-arrange recv_state as follows: IDLE (no traffic); RX_PAYLOAD (send byte+2 payload); POSTING (send byte, hold runctl ready=0); LOG_WR (send byte, hold log FIFO writeside busy); LOG_ERROR (inject parity error one cycle before soft_reset). |
| Injection | 1. AVMM write CONTROL with bit0=1 (soft_reset W1P pulse). 2. 16 mm_clk later, read STATUS. 3. On lvdspll side, send 1 clean RUN_SYNC. |
| Expected recovery | 1. Per CONTROL.soft_reset spec: clears recv FSM, host FSM, snapshot record, log FIFO read pointer. 2. recv_state=IDLE, host_state=IDLE. 3. Log FIFO read pointer reset (entries are re-visible from 0 if the write pointer wasn't reset -- see PROPOSAL). 4. The trailing RUN_SYNC processes normally. |
| PROPOSAL | **needs RTL lock.** soft_reset semantics on the log FIFO: DV_PLAN says "clears log FIFO read pointer", implying the write side is preserved. This means a soft_reset mid-LOG_WR could leave a half-written entry and the next pop returns a partial entry. Candidate (A): soft_reset clears BOTH sides of the log FIFO. Candidate (B): only read side cleared; mid-LOG_WR entry may leak as a torn entry on next pop. (A) is strongly preferred. Lock when RTL lands. |
| Coverage bins | `cov_err.soft_reset_in_state[IDLE,RX_PAYLOAD,POSTING,LOG_WR,LOG_ERROR]++` (5 bins). |
| Pass criteria | (a) no hang, (b) STATUS.recv_idle=1 and STATUS.host_idle=1 within 16 mm_clk of the CONTROL write, (c) no spurious runctl/upload beats, (d) post-reset RUN_SYNC scoreboard-matched, (e) 5 coverage bins all hit. |
| Status | planned |

### R010_log_flush_during_cmd

| Field | Value |
|-------|-------|
| Category | reset interaction / CONTROL.log_flush |
| Goal | Pulse CONTROL.log_flush (W1P) while a log entry is actively being written must not produce a torn entry. Either the whole 4-sub-word entry is present or the whole entry is absent after the flush completes. |
| Setup | 2 sub-cases: (a) log_flush BEFORE the 4-sub-word LOG_WR sequence begins for a given command; (b) log_flush AFTER the first sub-word of a 4-sub-word LOG_WR sequence. |
| Injection | 1. Send RUN_PREPARE + 4 payload bytes on synclink. 2. Sub-case (a): issue CONTROL.log_flush 0 cycles after RUN_PREPARE's last payload byte arrives (before POSTING completes). Sub-case (b): issue CONTROL.log_flush after scoreboard sees recv_state=LOG_WR and has confirmed 1 of 4 sub-words written. 3. Wait 64 mm_clk. 4. Read LOG_STATUS. 5. Drain via LOG_POP. |
| Expected recovery | 1. After flush: LOG_STATUS.rdempty=1, rdusedw=0. 2. LOG_POP returns 0 on every read. 3. Scoreboard checks: the scoreboard-shadowed log entries after the flush must match what the RTL flushed. No partial 4-sub-word sequence is visible. |
| PROPOSAL | **needs RTL lock.** Sub-case (b) is the hard one. Possible behaviors: (A) flush waits for the current entry to finish writing then flushes, guaranteeing atomicity; (B) flush drops the in-flight entry's remaining sub-words, leaving the already-popped 1-of-4 sub-word on the read side (torn); (C) flush drains the read side only and leaves the write side untouched, so the in-flight entry appears intact after the flush. (A) or (C) acceptable; (B) must be rejected at RTL review. |
| Coverage bins | `cov_err.log_flush_during_write++`, `cov_err.log_flush_before_write++`. |
| Pass criteria | (a) no hang, (b) rdempty=1 within 64 mm_clk of flush, (c) no torn entries popped, (d) recv_state returns to IDLE afterwards. |
| Status | planned |

---

## 6. Back-to-back Errors and Backpressure (R012, R013) -- 2 cases

### R012_runctl_ready_stuck_low

| Field | Value |
|-------|-------|
| Category | backpressure / sustained stall |
| Goal | runctl sink ready held low for 10000 lvdspll_clk cycles after a command arrives: the FSM must stall cleanly without asserting any error flag and must complete on release. |
| Setup | Full reset. runctl sink ready=1 initially. |
| Injection | 1. C0: send RUN_SYNC byte on synclink. 2. C1: drive runctl sink ready=0. 3. C1..C10001: hold runctl ready=0. 4. C10001: runctl ready=1. 5. Observe the one runctl fanout beat. 6. C10020: send one more RUN_SYNC. |
| Expected recovery | 1. During the stall: recv_state transitions to POSTING and host_state stalls with runctl valid=1, ready=0. STATUS.recv_idle=0, STATUS.host_idle=0. 2. RX_ERR_COUNT stays 0 (stall is not an error). 3. No watchdog / timeout in the FSM. 4. On release: one runctl beat observed (0x11). 5. RX_CMD_COUNT=1 after first command retires. 6. Second RUN_SYNC processes normally. |
| Coverage bins | `cov_err.runctl_stall[long]++`. |
| Pass criteria | (a) no hang within the expected stall window (FSM is allowed to stall indefinitely), (b) exactly 1 runctl beat observed after release, (c) RX_ERR_COUNT=0 throughout, (d) second command fanout observed, (e) scoreboard agrees on both commands. |
| Status | planned |

### R013_upload_ready_stuck_low

| Field | Value |
|-------|-------|
| Category | backpressure / upload path |
| Goal | upload sink ready held low after a RUN_PREPARE: upload FSM stalls, recv FSM behavior depends on whether upload backpressure is allowed to propagate to recv. On release, exactly one ack packet must emit. |
| Setup | Full reset. upload sink ready=1. runctl sink ready=1. |
| Injection | 1. Send RUN_PREPARE + 4 payload bytes on synclink at C0..C4. 2. C5: drive upload sink ready=0. 3. C5..C5005: hold. 4. C5005: upload ready=1. 5. C5030: send END_RUN (which also emits an upload ack). 6. C5030..C6030: upload ready=1. |
| Expected recovery | 1. During stall: upload FSM stalls with valid=1. 2. recv FSM: allowed to complete its log write and return to IDLE; POSTING of the RUN_PREPARE is not blocked by upload backpressure per DV_PLAN (runctl vs upload are independent sinks). 3. RX_CMD_COUNT increments to 1 after RUN_PREPARE is scoreboarded. 4. On upload release: exactly 1 K30.7 ack emits. 5. END_RUN processes normally and emits K29.7. Total upload beats = 2. |
| PROPOSAL | **needs RTL lock.** The decoupling between recv/host/upload FSMs is asserted by DV_PLAN but not yet locked in RTL. If the upload stall does back-propagate and block recv, the expected recovery changes: RX_CMD_COUNT would not increment until release. Lock when RTL lands. |
| Coverage bins | `cov_err.upload_stall[long]++`, `cov_cmd.upload_ack_class[K30.7,K29.7]++`. |
| Pass criteria | (a) no hang, (b) exactly 2 upload beats after release, (c) RX_ERR_COUNT=0, (d) RX_CMD_COUNT=2 at test end, (e) recv_state returns to IDLE. |
| Status | planned |

---

## 7. Error Counter Saturation

RX_ERR_COUNT is defined as "saturating" (DV_PLAN CSR map word 0x10). Width is 32 bits. A dedicated saturation case is NOT listed as a standalone R-ID because DV_PLAN does not assign one; it is covered in the existing R016 case and referenced here.

Plan drift note: If a saturation-specific test is required, it must be added to DV_PLAN section 6.4 first. See section 9.

---

## 8. Coverage Collector Additions

This document requires the following **new counter-based bins** in `runctl_mgmt_cov`, added to the existing bin lists in DV_PLAN section 5:

| Collector | New bin group | Bins | Hit source |
|-----------|---------------|------|------------|
| cov_err | err_class | parity, decode, loss_sync (3 bins) | synclink monitor on error[2:0] != 0 |
| cov_err | err_state_entry | IDLE, RX_PAYLOAD, POSTING, LOG_WR (4 bins) | recv_state just before LOG_ERROR entry |
| cov_err | recovery_latency_bin | <=4, <=8, <=16, <=32 (4 bins) | cycles from LOG_ERROR entry to IDLE |
| cov_err | truncated_cmd | RUN_PREPARE, RESET, STOP_RESET, ADDRESS (4 bins) | command byte of a truncated or aborted command |
| cov_err | mid_cmd_reset | lvdspll, mm, soft (3 bins) | reset kind sampled mid-command |
| cov_err | soft_reset_in_state | IDLE, RX_PAYLOAD, POSTING, LOG_WR, LOG_ERROR (5 bins) | recv_state at the cycle soft_reset fires |
| cov_err | log_fifo_full | 1 bin | LOG_STATUS.rdfull observed 1 |
| cov_err | log_pop_empty | 1 bin | LOG_POP issued while rdempty=1 |
| cov_err | log_flush_during_write | 1 bin | CONTROL.log_flush fired while recv_state=LOG_WR |
| cov_err | log_flush_before_write | 1 bin | CONTROL.log_flush fired while recv_state in {RX_PAYLOAD, POSTING} |
| cov_err | csr_oob_read | 1 bin | AVMM read to addr 0x15..0x1F |
| cov_err | csr_oob_write | 1 bin | AVMM write to addr 0x15..0x1F |
| cov_err | local_cmd_busy_write | 1 bin | AVMM write to LOCAL_CMD with STATUS.local_cmd_busy=1 |
| cov_err | runctl_stall | short, long (2 bins) | longest-observed runctl ready=0 duration bin |
| cov_err | upload_stall | short, long (2 bins) | longest-observed upload ready=0 duration bin |
| cov_err | mixed_stream_hit | 1 bin | R016 pattern detected |
| cov_err | loss_sync_during_pause | 1 bin | R005/R006 pattern |
| cov_err | resume_after_pause_ok | 1 bin | R005B pattern |
| cov_err | scratch_reset_by_mm | 1 bin | R008 observation |
| cov_err | csr_access_during_reset | 1 bin | R008 observation |
| cov_err | log_fifo_saturate_policy | drop_old, drop_new (2 bins) | whichever R014 lock decides |

Total new bins introduced: 39. These must be added to DV_PLAN.md section 5 as part of the same signoff or flagged as a drift.

Also add one new bin to `cov_cmd`: `cov_cmd.cmd_byte_unknown` (already named in DV_PLAN section 5.2).

---

## 9. Plan Drift Notes

1. **R-IDs covered:** R001 through R017 (17 IDs, matches DV_PLAN section 6.4 count).
2. **No new R-IDs invented.** All cases above map 1:1 to DV_PLAN section 6.4 entries. R005 and R006 are each expanded into 2 sub-cases (sub-A and sub-B); R009 is expanded into 5 sub-cases (one per recv_state). This is internal structure, not new IDs.
3. **Counter saturation test missing from DV_PLAN.** RX_ERR_COUNT is saturating but no R-case checks the saturation boundary explicitly. Suggest adding a new R018_err_count_saturate to DV_PLAN section 6.4 that drives > 2^32 parity errors and confirms saturation at 0xFFFFFFFF. This is out-of-scope until DV_PLAN is amended.
4. **Coverage bin additions (section 8) are out-of-band.** They require a corresponding update to DV_PLAN section 5 to preserve bin-count signoff math.
5. **Ten cases flagged "needs RTL lock":** R004, R005, R008, R009, R010, R011, R013, R014, R015. These must be revisited and pinned once `rtl/runctl_mgmt_host.sv` exists.
6. **LOG_ERROR state encoding.** The RTL does not exist yet; the LOG_ERROR state label is this plan's name for the sink state. If the final RTL uses a different label (e.g. ERR_DROP, ERR_FLUSH), this document must be updated to match.
7. **Payload-watchdog.** DV_PLAN does not specify a payload watchdog. R005 sub-case B assumes indefinite hold in RX_PAYLOAD. If RTL adds a watchdog, that sub-case becomes an active abort check.
8. **Upload / runctl decoupling.** R013 assumes upload backpressure does NOT block the recv and host FSMs. This is a DV_PLAN implication but not explicitly asserted. Confirm at RTL lock.

---

## 10. Summary

Total R-series cases in this document: **17** (R001-R017).

| Category | Cases | IDs |
|----------|-------|-----|
| synclink link errors | 5 | R001, R002, R003, R016, R017 |
| malformed commands | 1 | R004 |
| payload truncation | 2 | R005, R006 |
| CSR violations | 3 | R011, R014, R015 |
| reset interactions | 4 | R007, R008, R009, R010 |
| sustained backpressure | 2 | R012, R013 |

Every case verifies (a) no hang, (b) fault detection via counter or status flag, (c) recovery to IDLE within a stated cycle budget, (d) post-recovery smoke traffic processes cleanly. Ten cases carry explicit "needs RTL lock" PROPOSALs for revisit after `rtl/runctl_mgmt_host.sv` is written.

---

## 11. Expansion: RTL-locked error-injection tests (R018..R100)

The cases below were authored after `rtl/runctl_mgmt_host.sv` (version 26.0.0) landed, so behaviors previously flagged "needs RTL lock" are now pinned against the source of truth. Each row is self-contained; use the same pass criteria framework as section 0.1 (no hang, detection, recovery, no leakage, counter correctness). Randomization is LCG-based in `mutrig_common_pkg` (no `rand`/`constraint` per Questa FSE Starter). The recv FSM encoding used below is the RTL's actual encoding: `RECV_IDLE=0x00`, `RECV_RX_PAYLOAD=0x01`, `RECV_LOGGING=0x02`, `RECV_LOG_ERROR=0x03`, `RECV_CLEANUP=0x04`.

**Format:** `| ID | Stimulus | Expected | Status |`

### 11.1 synclink error timing permutations (R018..R037)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| R018_synclink_parity_on_cmd_byte | recv in IDLE; lvds C0: valid=1, k=0, data=0x10 (RUN_PREPARE), error={0,1,0} (parity). C1..C8: valid=0. | error[1:0]!=0 takes priority in RECV_IDLE branch: recv -> LOG_ERROR -> CLEANUP -> IDLE in 3 cycles. `ev_rx_error` pulses, RX_ERR_COUNT+=1. No RX_PAYLOAD entry, no log, no fanout, RX_CMD_COUNT unchanged. | planned |
| R019_synclink_decode_on_cmd_byte | Same as R018 but error={0,0,1} (decode). | Identical path to R018 (parity/decode share the `error[1:0]!=2'b00` branch). RX_ERR_COUNT+=1. | planned |
| R020_synclink_parity_on_payload_byte_0_runprep | C0: RUN_PREPARE byte, error=0. C1: payload byte 0, error={0,1,0}. C2..C8: valid=0. | Path: IDLE -> RX_PAYLOAD (C0+1). In RX_PAYLOAD, error[1:0]!=0 -> LOG_ERROR -> CLEANUP -> IDLE. Partial payload32 discarded (recv_run_number not updated; CLEANUP does not latch snapshot). RX_ERR_COUNT+=1, RX_CMD_COUNT unchanged. | planned |
| R021_synclink_parity_on_payload_byte_1_runprep | C0: RUN_PREPARE. C1: payload byte 0 clean. C2: payload byte 1 with error={0,1,0}. C3..C8: valid=0. | Same abort path as R020; recv_payload_cnt was 1 when error hit, still aborted. RX_ERR_COUNT+=1. | planned |
| R022_synclink_parity_on_payload_byte_2_runprep | C0..C2: RUN_PREPARE + 2 clean payload bytes. C3: payload byte 2 with error={0,1,0}. | Abort in RX_PAYLOAD after 2 of 4 bytes shifted. RX_ERR_COUNT+=1, RUN_NUMBER shadow unchanged. | planned |
| R023_synclink_parity_on_payload_byte_3_runprep | C0..C3: RUN_PREPARE + 3 clean payload bytes. C4: final payload byte with error={0,1,0}. | RTL checks error before the "last byte" latch (line 464 vs 471 in `runctl_mgmt_host.sv`): error path wins, no snapshot latch, no log. RX_ERR_COUNT+=1. | planned |
| R024_synclink_decode_on_payload_byte_0_runprep | Same as R020 but error={0,0,1} (decode). | Same abort path. RX_ERR_COUNT+=1. | planned |
| R025_synclink_decode_on_payload_byte_1_runprep | Same as R021 but error={0,0,1}. | Same abort path. | planned |
| R026_synclink_decode_on_payload_byte_2_runprep | Same as R022 but error={0,0,1}. | Same abort path. | planned |
| R027_synclink_decode_on_payload_byte_3_runprep | Same as R023 but error={0,0,1}. | Same abort path. | planned |
| R028_synclink_loss_sync_on_cmd_byte | C0: valid=1, data=0x10, error={1,0,0} (loss_sync). C1..C8: valid=0. | In RECV_IDLE the `error[2]==0` guard fails, so the byte is silently ignored: no state change, no ev_rx_error, no counter change, no log. (RTL only flags loss_sync inside RX_PAYLOAD.) Document deviation from DV_PLAN section 6.4 which expects RX_ERR_COUNT+=1 on every loss_sync byte. | planned |
| R029_synclink_loss_sync_on_payload_byte_0 | C0: RUN_PREPARE clean. C1: payload byte 0 with error={1,0,0}. | In RX_PAYLOAD, error[2] path: recv -> LOG_ERROR -> CLEANUP -> IDLE. RX_ERR_COUNT+=1, partial payload discarded. | planned |
| R030_synclink_loss_sync_on_payload_byte_1 | C0..C1: RUN_PREPARE + 1 payload. C2: error={1,0,0}. | Same abort path as R029. | planned |
| R031_synclink_loss_sync_on_payload_byte_2 | C0..C2: RUN_PREPARE + 2 payload. C3: error={1,0,0}. | Same abort path. | planned |
| R032_synclink_loss_sync_on_payload_byte_3 | C0..C3: RUN_PREPARE + 3 payload. C4: error={1,0,0}. | Same abort path; error gate wins before final latch. RX_ERR_COUNT+=1, RUN_NUMBER unchanged. | planned |
| R033_synclink_loss_sync_transient_1cyc | Idle. C0: hold error[2]=1 for exactly 1 cycle with valid=0 (pure idle flap). C1..C8: idle. | Loss_sync observed in IDLE with valid=0: RTL ignores the byte entirely (no valid high, no state change). No counter movement. Post-flap smoke RUN_SYNC processes normally. | planned |
| R034_synclink_loss_sync_transient_16cyc | Idle recv. Assert error[2]=1 with valid=0 for 16 lvds cycles. Then clean RUN_SYNC. | No state change during flap (recv only reacts to valid=1 bytes). Smoke RUN_SYNC increments RX_CMD_COUNT=1. RX_ERR_COUNT stays 0. | planned |
| R035_synclink_loss_sync_transient_1024cyc | Same as R034 but for 1024 cycles. Smoke traffic afterwards. | Same as R034. Verifies no latent "link flap" counter exists (RTL has none). | planned |
| R036_synclink_all_three_bits_mid_payload | C0..C1: RUN_PREPARE + 1 payload. C2: data=0xAA, error={1,1,1}. | RTL checks error[2] first (line 461). Loss_sync wins: LOG_ERROR -> CLEANUP -> IDLE. RX_ERR_COUNT+=1 (single increment; no double-count of parity+decode+loss_sync). | planned |
| R037_synclink_error_on_idle_k_byte | Idle recv. C0: valid=1, k=1, data=0x1C (comma), error={0,1,0}. C1..C8: valid=0. | In RECV_IDLE the error[1:0]!=0 branch fires regardless of k: recv -> LOG_ERROR -> CLEANUP -> IDLE, RX_ERR_COUNT+=1. Document deviation: DV_PLAN implies errors on k-bytes are ignored, but the RTL counts them because it tests error bits before the k-bit gate. | planned |

### 11.2 Unknown command byte (R038..R052)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| R038_unknown_cmd_byte_00h | C0: valid=1, k=0, data=0x00, error=0. | `cmd_is_known(0x00)=0` -> IDLE goes straight to RECV_CLEANUP (line 449-450). No ev_cmd_accepted, RX_CMD_COUNT unchanged. No runctl beat, no log, no upload ack. Recovery in 2 cycles. | planned |
| R039_unknown_cmd_byte_01h | Same pattern with data=0x01. | Same as R038: silent drop. | planned |
| R040_unknown_cmd_byte_0Fh | data=0x0F (boundary below known 0x10). | Silent drop. | planned |
| R041_unknown_cmd_byte_15h | data=0x15 (gap between RUN_* group and RESET group). | Silent drop. | planned |
| R042_unknown_cmd_byte_1Fh | data=0x1F. | Silent drop. | planned |
| R043_unknown_cmd_byte_20h | data=0x20. | Silent drop. | planned |
| R044_unknown_cmd_byte_2Fh | data=0x2F. | Silent drop. | planned |
| R045_unknown_cmd_byte_34h | data=0x34 (boundary above known 0x33). | Silent drop. | planned |
| R046_unknown_cmd_byte_3Fh | data=0x3F. | Silent drop. | planned |
| R047_unknown_cmd_byte_41h | data=0x41 (just above CMD_ADDRESS=0x40). | Silent drop. | planned |
| R048_unknown_cmd_byte_7Fh_via_local | AVMM write LOCAL_CMD={0x24'h000000, 0x7F}. | local_cmd path in RECV_IDLE: `cmd_is_known(0x7F)=0` -> RECV_CLEANUP (line 434-435). local_cmd_consume asserted, busy clears, no fanout, no log, RX_CMD_COUNT unchanged. Second write should not be blocked indefinitely. | planned |
| R049_unknown_cmd_byte_80h_via_local | AVMM LOCAL_CMD={24'h000000, 0x80}. | Same as R048. | planned |
| R050_unknown_cmd_byte_AAh | synclink data=0xAA, k=0, error=0. | Silent drop, recv returns to IDLE in 2 cycles. | planned |
| R051_unknown_cmd_byte_FFh | data=0xFF. | Silent drop. | planned |
| R052_unknown_cmd_then_valid_runsync | C0: unknown 0x77. C1..C3: valid=0. C4: clean RUN_SYNC (0x11). | 0x77 dropped in CLEANUP by C0+2. RUN_SYNC at C4 processes normally: RX_CMD_COUNT=1, one runctl beat, one log entry. Verifies no residual state from unknown drop. | planned |

### 11.3 Malformed / truncated payload (R053..R062)

The RTL has **no payload watchdog**. In RECV_RX_PAYLOAD the FSM waits indefinitely for the next `valid=1, k=0` byte. k=1 bytes mid-payload are silently ignored (line 467 gates on `asi_synclink_data[8]==1'b0` with no else branch). These rows document the observed behavior; flag as an RTL lock deviation from DV_PLAN which assumes possible resync on truncation.

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| R053_runprep_zero_payload_then_new_cmd | C0: RUN_PREPARE. C1..C10: valid=0. C11: new cmd byte data=0x11 (RUN_SYNC, k=0). | FSM is in RX_PAYLOAD at C11. Byte 0x11 is **shifted as payload data**, not recognized as a new command. recv_payload_cnt advances to 1. No RX_CMD_COUNT change. No RUN_SYNC processing. Document RTL gap: the parser cannot resync on command-byte boundaries. | planned |
| R054_runprep_1_of_4_payload_then_new_cmd | C0: RUN_PREPARE. C1: payload byte 0. C2: data=0x11 (k=0). | Same as R053; 0x11 absorbed as payload byte 1. No RUN_SYNC fanout. | planned |
| R055_runprep_2_of_4_payload_then_new_cmd | C0..C2: RUN_PREPARE + 2 payload. C3: data=0x13 (k=0). | 0x13 absorbed as payload byte 2. No END_RUN fanout. | planned |
| R056_runprep_3_of_4_payload_then_new_cmd | C0..C3: RUN_PREPARE + 3 payload. C4: data=0x14 (k=0). | 0x14 absorbed as payload byte 3, completing the payload. FSM latches recv_run_number (with junk content) and transitions to RECV_LOGGING. Produces one runctl beat for 0x10 (RUN_PREPARE) carrying garbage run_number. Document as known aliasing hazard. | planned |
| R057_reset_1_of_2_payload_then_new_cmd | C0: CMD_RESET (0x30). C1: mask byte 0 (0x12). C2: data=0x31 (k=0, would be STOP_RESET). | 0x31 absorbed as mask byte 1; RESET completes with recv_reset_assert_mask={0x12,0x31}=0x1231. dp/ct_hard_reset pulses via host FSM. No STOP_RESET processing. | planned |
| R058_reset_zero_payload_then_new_cmd | C0: CMD_RESET. C1..C4: valid=0. C5: data=0x30 (another RESET byte). | 0x30 absorbed as mask byte 0. FSM still in RX_PAYLOAD needing 1 more byte. Document RTL gap. | planned |
| R059_stop_reset_1_of_2_payload_then_new_cmd | C0: CMD_STOP_RESET (0x31). C1: byte 0. C2: data=0x32 (k=0). | 0x32 absorbed as mask byte 1; STOP_RESET completes with release_mask={payload0,0x32}. | planned |
| R060_address_1_of_2_payload_then_new_cmd | C0: CMD_ADDRESS (0x40). C1: byte 0. C2: data=0x40 (k=0). | 0x40 absorbed as byte 1; ADDRESS latches recv_fpga_address, goes through LOGGING -> CLEANUP without runctl fanout (CMD_ADDRESS does not fan out, line 500). | planned |
| R061_kflag_mid_payload_runprep | C0: RUN_PREPARE (k=0). C1: payload byte 0 (k=0). C2: valid=1, k=1, data=0x1C (comma), error=0. C3..C6: valid=0. | In RX_PAYLOAD, `asi_synclink_data[8]==1` so the byte is **silently ignored** (line 467 has no else). recv_payload_cnt unchanged. FSM remains in RX_PAYLOAD. Document RTL gap: k-bytes mid-payload do not abort. | planned |
| R062_kflag_then_valid_byte_mid_payload | C0: RUN_PREPARE. C1: payload 0. C2: k=1 (ignored). C3: k=0 payload byte 1. C4: k=0 payload byte 2. C5: k=0 payload byte 3. | k byte at C2 is dropped (no effect). C3-C5 complete the payload (3+1=4 bytes total non-k shifts). FSM transitions to LOGGING. One runctl beat for RUN_PREPARE. RX_CMD_COUNT=1. | planned |

### 11.4 CSR error paths (R063..R077)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| R063_csr_read_0x15 | AVMM read addr=0x15. | Address falls in default arm of read case (line 1019): readdata=0, waitrequest=0 (1-cycle accept), no side effects. | planned |
| R064_csr_read_0x16 | AVMM read addr=0x16. | Same as R063. | planned |
| R065_csr_read_0x1F | AVMM read addr=0x1F. | Same as R063. | planned |
| R066_csr_write_0x15_reserved | AVMM write addr=0x15, data=0xDEADBEEF. | Default write arm (line 964): waitrequest=0 after 1 cycle, no state touched. Read-back of LAST_CMD, SCRATCH, RX_CMD_COUNT unchanged. | planned |
| R067_csr_write_0x1F_reserved | AVMM write addr=0x1F, data=0xCAFEBABE. | Same as R066. | planned |
| R068_csr_read_during_mm_reset | Assert mm_reset; issue AVMM read addr=CSR_SCRATCH while in reset; deassert; complete read. | During mm_reset `csr_state<=CSR_IDLE` and waitrequest default=1 (line 910). Master waitrequest stall until deassert. Post-release read returns SCRATCH=0 (reset default). No hang. | planned |
| R069_csr_write_during_mm_reset | mm_reset high; AVMM write SCRATCH=0xBEEF while reset. | waitrequest=1 throughout reset. Write is not latched (csr_scratch forced to 0 under mm_reset). Post-release read=0. | planned |
| R070_csr_simultaneous_read_write | Drive both avs_csr_read=1 and avs_csr_write=1 in CSR_IDLE same cycle. | Write branch has priority (line 928: `if (avs_csr_write)` wins over `else if (avs_csr_read)`). Readdata=0, write side-effect applied per addr. | planned |
| R071_csr_write_UID_ro | AVMM write addr=CSR_UID=0x00, data=0xFFFFFFFF. | Default arm (only CSR_UID case in read branch; write branch has no CSR_UID entry, falls to default): waitrequest=0 1 cycle, no effect. Read-back returns IP_UID parameter. | planned |
| R072_csr_write_STATUS_ro | AVMM write addr=CSR_STATUS=0x03, data=0xFFFFFFFF. | STATUS absent from write case -> default arm: no effect. Read returns live state. | planned |
| R073_csr_write_ACK_SYMBOLS_ro | AVMM write addr=CSR_ACK_SYMBOLS=0x14. | No effect (default arm). Read returns {RUN_END_ACK_SYMBOL, RUN_START_ACK_SYMBOL}. | planned |
| R074_csr_write_ro_shadow_group | AVMM writes to RUN_NUMBER, RESET_MASK, FPGA_ADDRESS, RECV_TS_L/H, EXEC_TS_L/H, GTS_L/H, RX_CMD_COUNT, RX_ERR_COUNT, LOG_STATUS (all RO). One write per addr, 11 sub-writes. | Each hits the default arm of the write case: 1-cycle accept, no effect. Read-back reflects shadowed live values, not written garbage. | planned |
| R075_csr_write_LOG_POP_ro | AVMM write addr=CSR_LOG_POP=0x12 twice. | CSR_LOG_POP absent from write case -> default arm, no effect. Subsequent reads still auto-pop correctly. | planned |
| R076_csr_read_LOG_POP_auto_pop_smoke | Push 4 clean RUN_SYNCs, confirm 4 log entries. Read LOG_POP 16 times. | First 16 reads return the 4 4-sub-word entries in order, each read toggles log_fifo_rdreq (line 1008-1015). Post-drain reads return 0 (empty branch). No RTL wait on pops. | planned |
| R077_csr_write_LOCAL_CMD_while_busy_stall | Hold runctl ready=0. T0: write LOCAL_CMD=0x12000000. T0+2: write LOCAL_CMD=0x14000000 while busy. | First write enters CSR_IDLE branch, captures local_cmd_word_mm, toggles local_cmd_req_mm. Second write: busy=1 -> CSR_LOCAL_WAIT, waitrequest=1 until busy clears (line 954-962). No command tear. AVMM watchdog budget 1024 mm_clk. | planned |

### 11.5 Reset interactions (R078..R092)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| R078_lvdspll_reset_in_recv_idle | recv in IDLE, no traffic. Assert lvdspll_reset 8 cycles. | State unchanged (already IDLE). On release, recv accepts next clean byte. No counter change. | planned |
| R079_lvdspll_reset_in_rx_payload | Send RUN_PREPARE + 2 payload. Assert lvdspll_reset for 8 cycles. | `lvds_fsm_rst` asserts, recv_state -> IDLE (line 372), recv_payload_cnt=0, recv_run_number unchanged shadow-side (mm domain owns shadows, only updated via snap_update toggle). Post-release smoke: send clean RUN_PREPARE, verify RX_CMD_COUNT=1. | planned |
| R080_lvdspll_reset_in_logging | Drive runctl ready=0 so recv stalls in RECV_LOGGING (pipe_r2h handshake pending). Assert lvdspll_reset. | FSM reset flushes logging state, pipe_r2h_start cleared, log_fifo_wrreq cleared. No runctl beat emitted. Post-release: send clean RUN_SYNC, verify normal fanout. | planned |
| R081_lvdspll_reset_in_log_error | Inject parity error (LOG_ERROR entry), then assert lvdspll_reset within 1 cycle. | `ev_rx_error` already pulsed (before reset latch), so RX_ERR_COUNT may or may not have incremented depending on exact timing; DV must check both possibilities (`rx_err_count_lvds` increment is in a separate always_ff also gated by lvds_fsm_rst). Document: current RTL resets rx_err_count_lvds via lvds_fsm_rst path -> counter cleared. | planned |
| R082_lvdspll_reset_in_cleanup | Drive recv into RECV_CLEANUP (any completion). Assert lvdspll_reset within 1 cycle. | State forced to IDLE. No residual pipe_r2h_start. Post-release smoke clean. | planned |
| R083_mm_reset_during_csr_read | AVMM master starts a read of RX_CMD_COUNT. While waitrequest is being sampled, assert mm_reset. | waitrequest re-asserts to 1 (mm_reset branch). readdatavalid never fires for the pending beat. Master watchdog sees waitrequest released after mm_reset deassert; next read returns rx_cmd_count_mm=0 (shadow reset on mm_reset). | planned |
| R084_mm_reset_during_csr_write_scratch | AVMM write SCRATCH=0xBEEFCAFE; within the same cycle assert mm_reset. | csr_scratch forced to 0 by mm_reset branch. Post-release read=0. No orphan state. | planned |
| R085_mm_reset_during_log_flush | Trigger CONTROL.log_flush while non-empty; assert mm_reset during the drain. | mm_reset forces csr_state->CSR_IDLE (line 908), rdreq cleared. Log FIFO mm-side read pointer is in the FIFO primitive, not reset by mm_reset (only by explicit drain). Document: after release, the FIFO still contains unpopped entries unless drained. | planned |
| R086_lvdspll_reset_during_upload_send | Trigger RUN_PREPARE (which produces an upload ack). While upload FSM is in UPL_SEND with ready=0, assert lvdspll_reset. | upload valid drops, no extra upload byte emitted on release. Host FSM reset. Post-release: next RUN_PREPARE produces a fresh ack. | planned |
| R087_lvdspll_reset_during_hard_reset_pulse | CMD_RESET delivered, dp_hard_reset / ct_hard_reset asserted (masks low). Assert lvdspll_reset while they are high. | dp/ct_hard_reset go low on lvdspll_reset (host FSM cleared). No stuck-high condition. | planned |
| R088_lvdspll_reset_coincident_with_parity_error | Idle recv. Same cycle: drive error={0,1,0} on a valid byte AND assert lvdspll_reset. | Synchronous reset has priority; recv_state forced IDLE, ev_rx_error suppressed by lvds_fsm_rst branch. RX_ERR_COUNT unchanged. Document as expected RTL behavior. | planned |
| R089_mm_reset_coincident_with_local_cmd_write | Same cycle: AVMM write LOCAL_CMD AND assert mm_reset. | csr_state forced CSR_IDLE, local_cmd_req_mm cleared. AVMM write dropped. local_cmd_word_mm=0. Post-release: a fresh LOCAL_CMD write works. | planned |
| R090_soft_reset_while_local_cmd_busy | Setup: AVMM write LOCAL_CMD=0x12000000, immediately observe busy. AVMM write CONTROL.soft_reset=1 while busy. | soft_reset toggles soft_reset_req_mm (line 937-940), csr_state->CSR_LOG_FLUSH. On lvds side, `soft_reset_req_lvds_seen` toggles `lvds_fsm_rst` which clears recv FSM including `local_cmd_consume_lvds`. local_cmd_busy_mm eventually clears via the acknowledge toggle. No AVMM hang. | planned |
| R091_soft_reset_and_log_flush_same_write | AVMM write CONTROL=0x03 (soft_reset[0]=1 AND log_flush[1]=1). | Both `if` branches execute in the CSR always_ff (both non-exclusive): soft_reset_req_mm toggles AND csr_state->CSR_LOG_FLUSH. FIFO drains, lvds FSM resets. Single combined effect; no corruption. | planned |
| R092_double_soft_reset_back_to_back | AVMM write CONTROL=0x01 twice at T0 and T0+1 mm_clk. | First write toggles soft_reset_req_mm and enters CSR_LOG_FLUSH (stalling the bus). Second write waitrequests until flush completes, then toggles soft_reset_req_mm again and re-enters LOG_FLUSH. Two lvds-side resets observed via the acknowledge toggle. No hang. | planned |

### 11.6 Overflow and saturation (R093..R100)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| R093_rx_cmd_count_saturate | Backdoor: drive rx_cmd_count_lvds to 0xFFFF_FFFE via scoreboard hook (or accelerated command stream). Inject 3 more clean commands. | After 1st: count=0xFFFF_FFFF. After 2nd: saturates at 0xFFFF_FFFF (line 781 guard). After 3rd: still 0xFFFF_FFFF. CSR read returns 0xFFFF_FFFF. | planned |
| R094_rx_err_count_saturate | Drive rx_err_count_lvds to 0xFFFF_FFFE. Inject 3 parity errors. | Saturates at 0xFFFF_FFFF per mirrored guard in the rx_err_count always_ff. | planned |
| R095_log_drop_count_saturate | Fill log FIFO to rdfull. Inject many more clean commands until log_drop_count_lvds reaches 0xFFFF_FFFE + 3. | `ev_log_drop` pulses on each over-full write attempt (line 525). Saturates at 0xFFFF_FFFF per guard. | planned |
| R096_log_fifo_exact_full_plus_one | Fill FIFO to exactly wrfull=1 (capacity known from dcfifo params). Inject one more clean command. | `log_fifo_wrfull=1` branch: ev_log_drop pulses, no log entry written, recv FSM still moves LOGGING->CLEANUP->IDLE (drop-new policy confirmed, line 515-526). RX_CMD_COUNT still increments. | planned |
| R097_log_fifo_full_then_flush_then_accept | Fill FIFO to rdfull. CONTROL.log_flush. After drain, inject 4 clean RUN_SYNCs. | Post-flush rdempty=1. New commands accepted with log entries. log_drop_count unchanged by flush. | planned |
| R098_runctl_ready_stuck_low_100k | Send RUN_SYNC. Hold runctl ready=0 for 100000 lvdspll cycles. Release. Send another RUN_SYNC. | recv in LOGGING (pipe_r2h_start high, waiting for pipe_r2h_done). No watchdog exists in RTL. On release, one runctl beat, recv -> CLEANUP -> IDLE. Second RUN_SYNC processes normally. RX_ERR_COUNT=0. | planned |
| R099_upload_ready_stuck_low_100k | Send RUN_PREPARE (with upload ack path). Hold upload ready=0 for 100000 cycles. Send END_RUN mid-stall (should enqueue behind). Release. | Upload FSM in UPL_SEND with valid=1 throughout. recv + host FSMs stall waiting for host handshake to complete (pipe_r2h coupling). Document: upload backpressure back-propagates to recv since pipe_r2h_done gates on upload-complete for ack-producing commands. Second command also stalls. No hang. | planned |
| R100_local_cmd_toggle_storm | AVMM writes LOCAL_CMD every mm_clk cycle for 64 cycles, alternating 0x12000000 / 0x14000000, ignoring busy polling. | First write accepted; subsequent writes stall on waitrequest in CSR_LOCAL_WAIT (line 959). Each commit consumes one writedata and pulses local_cmd_req_mm toggle. All 64 writes eventually retire in order. Scoreboard checks alternating 0x12/0x14 fanout on runctl (32 of each). No lost commands, no tear. | planned |

---

## 12. Expansion Summary (R018..R100)

New R-cases in this expansion: **83** (R018..R100). Total R-series now: **100** (R001..R100).

| Group | Range | Count |
|-------|-------|-------|
| synclink error timing permutations | R018..R037 | 20 |
| unknown command byte | R038..R052 | 15 |
| malformed / truncated payload | R053..R062 | 10 |
| CSR error paths | R063..R077 | 15 |
| reset interactions | R078..R092 | 15 |
| overflow, saturation, backpressure, CDC storms | R093..R100 | 8 |

### 12.1 Ambiguities found between DV_PLAN and RTL (to reconcile later)

1. **Loss_sync on an idle byte (R028 / R037).** DV_PLAN section 6.4 and section 0.2 of this file treat any `error[2:0]!=0` byte as an RX_ERR_COUNT increment. RTL only flags errors inside the `error[2]==0` branch in RECV_IDLE (line 438), so a pure loss_sync (`error={1,0,0}`) in IDLE is **silently ignored** and does NOT increment RX_ERR_COUNT. Parity/decode on a k=1 idle byte, by contrast, DOES increment because the `error[1:0]!=2'b00` check fires before the `asi_synclink_data[8]==0` gate.
2. **Unknown command byte (R004, R038..R052).** R004's PROPOSAL was A-or-B. RTL locks **candidate A**: unknown bytes go IDLE -> RECV_CLEANUP without setting ev_cmd_accepted. RX_CMD_COUNT does NOT increment. Needs update to R004 PROPOSAL.
2b. **Unknown command via LOCAL_CMD (R048, R049).** Same lock: LOCAL_CMD path also routes unknown bytes through RECV_CLEANUP without counter bump (line 432-435).
3. **Payload truncation has no resync (R053..R060).** RTL has no payload watchdog and no command-boundary resync — any byte received in RX_PAYLOAD is shifted as payload data regardless of whether it is itself a valid command byte. DV_PLAN R005 sub-case B's assumption of "indefinite hold" is correct. R053..R060 document that truncation leaks into the next command as payload aliasing; this is a latent parser hazard that should be raised for an RTL fix (add a payload watchdog or require a comma between commands).
4. **k-flag mid-payload silently ignored (R061, R062).** RTL line 467 has no else branch for `asi_synclink_data[8]==1` in RECV_RX_PAYLOAD, so k-bytes are dropped with no state change. DV_PLAN does not specify this behavior either way — lock as "k-byte mid-payload is a no-op".
5. **Loss_sync wins over parity/decode (R036).** Confirmed — line 461 checks `error[2]` before `error[1:0]`. RX_ERR_COUNT increments exactly once per errored byte. Matches DV_PLAN section 0.2 (loss_sync dominates).
6. **Log FIFO drop policy (R014, R095, R096).** RTL locks **drop-new** (line 515-526): if `log_fifo_wrfull` then `ev_log_drop` pulses and the write is dropped, existing entries preserved. R014 PROPOSAL should pin `log_fifo_saturate_policy[drop_new]`.
7. **Soft_reset FIFO scope (R009).** RTL: `lvds_fsm_rst` clears recv FSM and write-side log state; the mm-side log drain path (CSR_LOG_FLUSH) is triggered in parallel via the CSR always_ff (line 937-940). Both sides of the FIFO drain. Matches DV_PLAN candidate (A). Pin the lock.
8. **CSR OOB (R015, R063..R067).** RTL confirms 1-cycle accept + 0 readdata + no side effects. No waitrequest stall. Matches DV_PLAN's "no waitrequest" intent.
9. **CSR read+write same cycle (R070).** RTL: write priority (line 928 `if..else if`). DV_PLAN does not explicitly state this — lock as "write priority".
10. **Upload backpressure propagation (R013, R099).** RTL ties pipe_r2h_done to the host FSM which completes only after upload-ack commands emit their ack. Upload stall DOES back-propagate to recv for ack-producing commands. R013's "decoupled" assumption is wrong for RUN_PREPARE/END_RUN; for non-ack commands (RUN_SYNC, START_RUN, ABORT_RUN, RESET, STOP_RESET, ADDRESS) it is correct. This is a DV_PLAN section 2 update.
