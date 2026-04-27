# runctl_mgmt_host DV — Edge Cases

**Companion docs:** `README.md`, `DV_PLAN.md`, `DV_HARNESS.md`,
`DV_BASIC.md`, `DV_CROSS.md`, `DV_ERROR.md`, `DV_PROF.md`,
`BUG_HISTORY.md`

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Canonical ID range:** E001-E020 (exactly as listed in DV_PLAN.md section 6.2)
**Total:** 20 cases
**Method:** All directed (D)

These tests exercise boundary conditions for `runctl_mgmt_host`: timing corners on the `lvdspll_clk` datapath, backpressure held through multiple commands, 48-bit gts rollover, log FIFO near-full / near-empty, CDC phase sweeps between `mm_clk` and `lvdspll_clk`, and combinational races inside the CSR block. Every case names the exact timing condition under which the corner must be provoked. Clock frequency ratios and phase relationships are stated where CDC behavior is load-bearing.

Default clock config unless stated otherwise: `lvdspll_clk = 125 MHz`, `mm_clk = 156.25 MHz`, asynchronous, free-running phase sweep across test seed.

---

## E001_runctl_ready_held_low

| Field | Value |
|---|---|
| ID | E001_runctl_ready_held_low |
| Category | Downstream backpressure / recv FSM stall |
| Goal | Confirm that `runctl_host` FSM holds in POSTING while `runctl_ready=0`, that `synclink_recv` blocks waiting for the handshake, and that exactly one transaction is emitted when ready releases. |

**Setup**

- Reset complete, CSR defaults, `runctl_sink_agent` programmed to drive `runctl_ready=0` for 64 `lvdspll_clk` cycles after first observed `valid`.
- Upload sink ready high, CSR idle, log FIFO empty.

**Stimulus sequence**

1. Send a single `CMD_RUN_SYNC` (0x11) byte via synclink at `lvdspll_clk` edge N.
2. Observe `runctl_valid` assert within a few cycles.
3. Hold `runctl_ready=0` for exactly 64 consecutive `lvdspll_clk` cycles after `valid` first asserts.
4. Read STATUS at mm_clk during the stall (reads must not disturb the stall).
5. Release `runctl_ready=1` on cycle 65.
6. Read STATUS again once recv returns to IDLE.

**Expected result**

1. `runctl_valid` stays high for the entire 64-cycle stall; `runctl_data` stable at 0x11.
2. STATUS.host_state_enc reports the POSTING encoding throughout the stall; STATUS.host_idle=0, STATUS.recv_idle=0.
3. Exactly one handshake completes on cycle 65 (single-cycle `valid & ready`).
4. RX_CMD_COUNT increments by 1 total; one log entry (4 sub-words) becomes available via LOG_POP.
5. Post-stall STATUS reads recv_idle=1, host_idle=1.

**Coverage bins hit**

- `cov_cmd.cmd_byte_synclink[0x11]`
- `cov_cross.C1[RUN_SYNC x held-low]`
- `cov_cross.C2[latency=max x state=POSTING]`

**Pass criteria**

- Single runctl beat, no additional beats, no FSM hang, RX_CMD_COUNT delta exactly 1, log FIFO rdusedw increments by 4.
- No SVA firings.

**Status:** planned

---

## E002_upload_ready_held_low

| Field | Value |
|---|---|
| ID | E002_upload_ready_held_low |
| Category | Upload backpressure / ack emission stall |
| Goal | Confirm `rc_pkt_upload` FSM stalls on `upload_ready=0` for 128 cycles and emits exactly one ack packet on release, with no duplicated sop/eop. |

**Setup**

- `upload_sink_agent` programmed to drive `upload_ready=0` starting at the cycle before the first `upload_valid` and hold for 128 `lvdspll_clk` cycles.
- runctl sink ready high.

**Stimulus sequence**

1. Send `CMD_RUN_PREPARE` (0x10) + 4 payload bytes (run_number=0xCAFEBABE) via synclink.
2. Observe `upload_valid` assert.
3. Hold `upload_ready=0` for exactly 128 `lvdspll_clk` cycles.
4. Release `upload_ready=1` on cycle 129.
5. Wait for `upload_eop`.

**Expected result**

1. `upload_valid` remains asserted throughout the stall; `upload_data`, `upload_sop`, `upload_eop` k-flags stable.
2. No spurious transitions on `upload_sop`/`upload_eop` during the stall.
3. After release, the ack packet completes in its native beat count with exactly one sop at the start and one eop at the end.
4. The ack data[35:32] k-flag field contains the RUN_START_ACK_SYMBOL (0xFE) per ACK_SYMBOLS.
5. RUN_NUMBER CSR reads 0xCAFEBABE.

**Coverage bins hit**

- `cov_cmd.upload_ack_class[K30.7]`
- `cov_cmd.cmd_payload_runprep[mid]`
- `cov_cross.C1[RUN_PREPARE x held-low]`

**Pass criteria**

- Exactly one (sop, eop) pair observed. No beat repeated. No FSM hang.

**Status:** planned

---

## E003_back_to_back_cmds

| Field | Value |
|---|---|
| ID | E003_back_to_back_cmds |
| Category | Minimum inter-command idle gap |
| Goal | Stream 16 single-byte commands with zero idle cycles between consecutive bytes on synclink. Confirm the recv FSM returns to a state that accepts the next byte on the very next `lvdspll_clk` cycle after posting. |

**Setup**

- runctl and upload sinks fully ready.
- Scoreboard primed to expect 16 log entries.

**Stimulus sequence**

1. On consecutive `lvdspll_clk` cycles N, N+1, ..., N+15 drive synclink `valid=1` with command bytes 0x11, 0x12, 0x14, 0x11, 0x32, 0x33, 0x11, 0x12, 0x11, 0x32, 0x33, 0x14, 0x11, 0x32, 0x33, 0x12 (no payload commands).
2. Drop `valid=0` on cycle N+16.
3. Wait until STATUS.recv_idle=1 and STATUS.host_idle=1.

**Expected result**

1. Every byte is captured: the recv FSM transitions IDLE -> POSTING -> IDLE once per byte without skipping.
2. `runctl` source emits 16 one-beat transactions in the exact order sent.
3. RX_CMD_COUNT increments by exactly 16.
4. LOG_STATUS.rdusedw = 64 (16 entries x 4 sub-words) or the log-depth-limited equivalent with no loss.
5. No assertion of RX_ERR_COUNT.

**Coverage bins hit**

- `cov_cmd.cmd_byte_synclink[0x11], [0x12], [0x14], [0x32], [0x33]`
- `cov_cross.C1[... x continuous-ready]`

**Pass criteria**

- All 16 transactions observed on runctl, all 16 logged, no drops, no duplicates.

**Status:** planned

---

## E004_log_fifo_near_full

| Field | Value |
|---|---|
| ID | E004_log_fifo_near_full |
| Category | Log FIFO occupancy boundary (near-full) |
| Goal | Drive `LOG_STATUS.rdusedw` to within one command-sized slot of the FIFO depth. Verify behavior when an additional command arrives at the boundary and when one sub-word past depth is produced. |

**Setup**

- Log FIFO empty. No LOG_POP traffic. `log_flush` not pulsed.
- Let `LOG_RD_DEPTH` be the parameterized FIFO read-side depth (read 32-bit side).
- Commands consume 4 sub-words each; target state is `rdusedw = LOG_RD_DEPTH - 4`.

**Stimulus sequence**

1. Send single-byte commands (0x11) back-to-back until `rdusedw = LOG_RD_DEPTH - 4`. Poll LOG_STATUS between bursts.
2. Read LOG_STATUS; confirm `rdfull=0`, `rdempty=0`.
3. Send one more single-byte command (slot N+1). This should exactly fill the FIFO.
4. Read LOG_STATUS; confirm `rdfull=1`.
5. Send one additional command (overflow candidate).
6. Read LOG_STATUS and RX_CMD_COUNT.

**Expected result**

1. At step 2, `rdusedw = LOG_RD_DEPTH - 4`, `rdfull=0`.
2. At step 4, `rdusedw` reaches max, `rdfull=1`.
3. At step 5 the RTL policy is followed: either the log write is dropped (scoreboard tracks drop) or held-off while the command still fans out on runctl. In either case no torn entry is produced and RX_CMD_COUNT still reflects the command on the datapath.
4. A subsequent LOG_POP burst drains the FIFO in strict FIFO order, matching the scoreboard.

**Coverage bins hit**

- `cov_cross.C4[near-full x burst=1]`

**Pass criteria**

- `rdfull` deasserts after burst drain. No sub-word duplicated or lost relative to RTL-policy scoreboard model.

**Status:** planned

---

## E005_log_pop_burst

| Field | Value |
|---|---|
| ID | E005_log_pop_burst |
| Category | LOG_POP burst / sub-word ordering |
| Goal | Pop 64 sub-words back-to-back from LOG_POP with zero idle cycles on the mm_clk AVMM side and confirm every sub-word matches the scoreboard in exact FIFO order. |

**Setup**

- Queue 16 mixed commands via synclink ahead of the pop burst (each producing 4 sub-words = 64 total).
- Wait for STATUS.host_idle=1 and `rdusedw=64`.

**Stimulus sequence**

1. Issue 64 consecutive AVMM reads to `0x12` (LOG_POP) on consecutive mm_clk cycles.
2. Capture every read data word.
3. After the burst, read LOG_STATUS.

**Expected result**

1. Sub-words 0..63 returned in strict FIFO order, matching the recv_ts / cmd / payload / exec_ts schema of the 16 logged commands.
2. Each 4-sub-word group internally consistent (recv_ts_hi, recv_ts_lo+cmd, payload, exec_ts).
3. LOG_STATUS.rdempty=1, rdusedw=0 after the burst.
4. A 65th LOG_POP read returns 0x00000000 (empty-read policy from section 3).

**Coverage bins hit**

- `cov_cross.C4[near-empty x burst=16]`
- `cov_csr.csr_addr_read[0x12]`

**Pass criteria**

- 64 reads match scoreboard byte-exact. 65th read is 0.

**Status:** planned

---

## E006_meta_invalid_page

| Field | Value |
|---|---|
| ID | E006_meta_invalid_page |
| Category | CSR field masking |
| Goal | Write the META selector with reserved upper bits set and confirm only `[1:0]` selects the page. |

**Setup**

- Reset defaults. META page tracked by scoreboard.

**Stimulus sequence**

1. Write META (0x01) = 0xFFFFFFFC (bits [1:0]=00, upper bits all set).
2. Read META. Record value.
3. Write META = 0xDEADBEE1.
4. Read META. Record value.
5. Write META = 0x12345672.
6. Read META. Record value.
7. Write META = 0xCAFEBAB3.
8. Read META. Record value.

**Expected result**

1. Step 2 returns the VERSION page payload.
2. Step 4 returns the DATE page payload.
3. Step 6 returns the GIT page payload.
4. Step 8 returns the INSTANCE_ID page payload.
5. Upper reserved bits of the selector latch are ignored (read-back of the selector itself, if exposed, masks to `[1:0]`).

**Coverage bins hit**

- `cov_csr.meta_page[0..3]`
- `cov_csr.csr_addr_write[0x01]`

**Pass criteria**

- All 4 pages returned correctly; no other CSR disturbed.

**Status:** planned

---

## E007_control_mask_dp_only

| Field | Value |
|---|---|
| ID | E007_control_mask_dp_only |
| Category | Reset mask combination |
| Goal | With `CONTROL.rst_mask_dp=1` and `rst_mask_ct=0`, a CMD_RESET must drive `ct_hard_reset` only; `dp_hard_reset` stays low. |

**Setup**

- Reset, clear CONTROL.
- Write CONTROL (0x02) with bit[4]=1, bit[5]=0 before any reset command.

**Stimulus sequence**

1. Read STATUS to confirm dp_hard_reset=0, ct_hard_reset=0.
2. Send CMD_RESET (0x30) + 16-bit assert mask = 0xA55A via synclink.
3. Sample `dp_hard_reset` and `ct_hard_reset` in the lvdspll domain across the 8 cycles after the last payload byte.
4. Read CSR RESET_MASK (0x07).
5. Read STATUS.

**Expected result**

1. `dp_hard_reset` stays low for all 8 sample cycles.
2. `ct_hard_reset` asserts within the expected latency and stays high.
3. RESET_MASK[15:0] = 0xA55A.
4. STATUS.dp_hard_reset=0, STATUS.ct_hard_reset=1.
5. Log entry present with payload = 0xA55A in bits [15:0] and zeros in [31:16] (reset entry layout).

**Coverage bins hit**

- `cov_csr.control_mask_combo[10]`
- `cov_cross.C5[dp_only x CMD_RESET]`
- `cov_cmd.cmd_byte_synclink[0x30]`

**Pass criteria**

- dp output never glitches during the test. ct output matches mask logic.

**Status:** planned

---

## E008_control_mask_ct_only

| Field | Value |
|---|---|
| ID | E008_control_mask_ct_only |
| Category | Reset mask combination |
| Goal | Symmetric to E007: `rst_mask_ct=1`, `rst_mask_dp=0`. |

**Setup**

- Reset, CONTROL bit[5]=1, bit[4]=0.

**Stimulus sequence**

1. Confirm dp_hard_reset=0, ct_hard_reset=0.
2. Send CMD_RESET (0x30) + 16-bit mask = 0x1234.
3. Sample both hard_reset outputs for 8 cycles.
4. Read RESET_MASK.
5. Read STATUS.

**Expected result**

1. `ct_hard_reset` stays low.
2. `dp_hard_reset` asserts.
3. RESET_MASK[15:0] = 0x1234.
4. STATUS.dp_hard_reset=1, STATUS.ct_hard_reset=0.

**Coverage bins hit**

- `cov_csr.control_mask_combo[01]`
- `cov_cross.C5[ct_only x CMD_RESET]`

**Pass criteria**

- ct output never glitches; dp output asserts cleanly.

**Status:** planned

---

## E009_control_mask_both

| Field | Value |
|---|---|
| ID | E009_control_mask_both |
| Category | Reset mask combination (full mask) |
| Goal | With both masks set, CMD_RESET leaves both hard_reset outputs low, but the RESET_MASK CSR still captures the payload. |

**Setup**

- Reset, CONTROL [5:4] = 2'b11.

**Stimulus sequence**

1. Send CMD_RESET (0x30) + mask = 0xFFFF.
2. Sample both hard_reset outputs for 16 cycles.
3. Read RESET_MASK and STATUS.
4. Send CMD_STOP_RESET (0x31) + release mask = 0xFFFF while masks still set.
5. Read RESET_MASK again.

**Expected result**

1. `dp_hard_reset`, `ct_hard_reset` both remain 0.
2. RESET_MASK[15:0] = 0xFFFF after step 3.
3. STATUS.dp_hard_reset=0, STATUS.ct_hard_reset=0.
4. After step 4, RESET_MASK[31:16] = 0xFFFF; outputs still 0.
5. Both commands show up in the log with correct payloads.

**Coverage bins hit**

- `cov_csr.control_mask_combo[11]`
- `cov_cross.C5[both x CMD_RESET], [both x CMD_STOP_RESET]`

**Pass criteria**

- No assertion of hard_reset outputs in either phase; CSR still updates.

**Status:** planned

---

## E010_gts_wrap

| Field | Value |
|---|---|
| ID | E010_gts_wrap |
| Category | 48-bit gts counter rollover |
| Goal | Exercise the 48-bit gts counter across its upper boundary and confirm `recv_ts` and `exec_ts` captured per-command walk cleanly across the wrap without torn upper/lower halves. |

**Setup**

- Testbench forces the gts counter to `0xFFFF_FFFF_FFF0` via the gts input at reset-exit.
- Log FIFO empty, CSR defaults.

**Stimulus sequence**

1. Resume normal clocks. gts begins counting at `0xFFFF_FFFF_FFF0`.
2. Send `CMD_RUN_SYNC` (0x11) approximately 2 `lvdspll_clk` cycles before the wrap (target capture at `~0xFFFF_FFFF_FFFE`).
3. Send another 0x11 one cycle before the wrap.
4. Send a third 0x11 one cycle after the wrap (expected capture `~0x0000_0000_0001`).
5. Send a fourth 0x11 well past the wrap.
6. Drain the 4 log entries via LOG_POP (16 sub-words).
7. Read RECV_TS_L/H and EXEC_TS_L/H after each command as a sanity cross-check.

**Expected result**

1. Commands 1 and 2 produce recv_ts near `0xFFFF_FFFF_FFFx`.
2. Command 3 produces recv_ts near `0x0000_0000_000x` with [47:32] cleanly incremented.
3. Every logged 48-bit recv_ts and exec_ts is monotone (allowing the 48-bit wrap) and internally consistent: the upper half matches the lower half's epoch.
4. No combination where recv_ts[47:32] lags recv_ts[31:0] by one epoch.
5. CSR readback of RECV_TS_H after RECV_TS_L is atomic (same snapshot rule as GTS_L/H).

**Coverage bins hit**

- `cov_cmd.cmd_byte_synclink[0x11]` (already hit)
- Edge-only: gts wrap observed by scoreboard.

**Pass criteria**

- Zero torn-epoch readings across 4 logged commands and 4 CSR snapshots.

**Status:** planned

---

## E011_address_no_fanout

| Field | Value |
|---|---|
| ID | E011_address_no_fanout |
| Category | CMD_ADDRESS fanout suppression |
| Goal | Confirm CMD_ADDRESS (0x40) updates `FPGA_ADDRESS` and LAST_CMD but never issues any runctl source transaction. |

**Setup**

- runctl_sink ready high, monitor counts runctl beats.
- Scoreboard transaction counter at 0 for runctl.

**Stimulus sequence**

1. Send CMD_ADDRESS (0x40) + 16-bit payload = 0xBEEF.
2. Wait 64 `lvdspll_clk` cycles.
3. Read FPGA_ADDRESS (0x08), LAST_CMD (0x04), RX_CMD_COUNT.
4. Send CMD_ADDRESS again with payload 0x1234 and repeat the checks.

**Expected result**

1. Zero beats observed on runctl source during the entire test.
2. FPGA_ADDRESS[15:0] = 0xBEEF after step 3; `[31]` sticky-valid=1.
3. LAST_CMD[7:0] = 0x40; LAST_CMD[31:16] = 0xBEEF.
4. After step 4, FPGA_ADDRESS[15:0] = 0x1234; sticky-valid still 1.
5. RX_CMD_COUNT increments by 2. Log entry present for both (payload field = address).
6. No upload ack packets.

**Coverage bins hit**

- `cov_cmd.cmd_byte_synclink[0x40]`
- `cov_cmd.cmd_payload_address[mid]`

**Pass criteria**

- runctl beat count stays exactly 0. FPGA_ADDRESS tracks latest payload.

**Status:** planned

---

## E012_runctl_ready_toggle_1cycle

| Field | Value |
|---|---|
| ID | E012_runctl_ready_toggle_1cycle |
| Category | 1-cycle ready toggle stress |
| Goal | With `runctl_ready` toggling every `lvdspll_clk` cycle (50% duty, 1-cycle period), stream a long sequence of commands and confirm no drops, no duplicates, and bounded latency. |

**Setup**

- `runctl_sink_agent` programmed to drive `ready` = alternating 0,1,0,1,... starting at reset exit, free-running.
- Upload sink ready high.

**Stimulus sequence**

1. Send 256 single-byte commands (mix of 0x11, 0x12, 0x14, 0x32, 0x33) back-to-back on synclink.
2. Wait for STATUS.recv_idle=1 and STATUS.host_idle=1.
3. Read RX_CMD_COUNT and LOG_STATUS.rdusedw.

**Expected result**

1. Every command handshake lands on a `ready=1` phase; the host FSM never skips.
2. RX_CMD_COUNT increments by exactly 256.
3. All 256 runctl transactions observed in order.
4. No log sub-words lost (rdusedw + previously popped = 256*4, modulo any LOG_POP during test).
5. No FSM hang, no SVA firings.

**Coverage bins hit**

- `cov_cross.C2[latency=1 x POSTING]`
- `cov_cross.C1[many_classes x toggled]`

**Pass criteria**

- 256 in, 256 out, in order.

**Status:** planned

---

## E013_local_cmd_busy_block

| Field | Value |
|---|---|
| ID | E013_local_cmd_busy_block |
| Category | LOCAL_CMD write-while-busy race |
| Goal | Confirm that a LOCAL_CMD write on the exact mm_clk cycle that STATUS.local_cmd_busy=1 is rejected by the CSR write path and does not perturb the in-flight command. |

**Setup**

- Reset, CSR idle. CONTROL default. mm/lvdspll clock ratio as default (156.25/125 MHz, async).
- `runctl_sink_agent` adds a 32-cycle ready latency to lengthen the local_cmd busy window.

**Stimulus sequence**

1. AVMM write LOCAL_CMD (0x13) = 0x12000000 (CMD_START_RUN).
2. On the very next mm_clk cycle, read STATUS to confirm local_cmd_busy=1.
3. While local_cmd_busy=1, AVMM write LOCAL_CMD = 0x14000000 (CMD_ABORT_RUN).
4. Poll STATUS until local_cmd_busy=0.
5. AVMM read LOCAL_CMD.
6. Observe the runctl source.

**Expected result**

1. Exactly one runctl beat emitted: data = 0x12 (CMD_START_RUN).
2. The second write (step 3) is silently dropped: scoreboard sees the write response but no second runctl beat.
3. LOCAL_CMD readback (step 5) returns the last successfully submitted word = 0x12000000.
4. RX_CMD_COUNT delta = 1. Log FIFO holds 4 sub-words for CMD_START_RUN only.

**Coverage bins hit**

- `cov_csr.csr_addr_write[0x13]`
- `cov_cmd.cmd_byte_local[0x12]`

**Pass criteria**

- Rejected write leaves no trace on runctl; busy bit observed high between the two writes.

**Status:** planned

**Related implemented reproducer**

- `runctl_mgmt_host_local_cmd_backpressure_test` is the current direct
  standalone regression for the adjacent held-write / waitrequest-release bug
  tracked as `BUG-001-R`. It does not yet cover the exact explicit second-write
  drop described in this planned E013 case.

---

## E014_soft_reset_idle

| Field | Value |
|---|---|
| ID | E014_soft_reset_idle |
| Category | CONTROL.soft_reset at idle |
| Goal | Pulse soft_reset while the FSMs are IDLE and the log FIFO holds entries. Confirm FSMs remain idle, snapshot CSRs clear, and log FIFO read pointer is cleared (per spec). |

**Setup**

- Send 4 commands to populate the log FIFO and snapshot CSRs (LAST_CMD, FPGA_ADDRESS, RUN_NUMBER, RESET_MASK).
- Wait for STATUS.recv_idle=1 and STATUS.host_idle=1.
- Capture pre-reset log rdusedw.

**Stimulus sequence**

1. AVMM write CONTROL = 0x00000001 (soft_reset W1P).
2. Wait 8 mm_clk cycles.
3. Read STATUS.
4. Read LOG_STATUS.
5. Read LAST_CMD, FPGA_ADDRESS, RUN_NUMBER, RESET_MASK.
6. Issue one new single-byte command via synclink and drain it.

**Expected result**

1. STATUS after the pulse: recv_idle=1, host_idle=1.
2. LOG_STATUS after the pulse: rdempty=1, rdusedw=0 (log read pointer cleared).
3. Snapshot CSRs return to their post-reset defaults (LAST_CMD=0, FPGA_ADDRESS=0, RUN_NUMBER=0, RESET_MASK=0).
4. The new command in step 6 processes normally; LAST_CMD updates.

**Coverage bins hit**

- `cov_csr.control_writeable_bits[bit0]`
- `cov_csr.csr_addr_write[0x02]`

**Pass criteria**

- Clean idle after pulse, FIFO empty, new command still processable.

**Status:** planned

---

## E015_log_flush

| Field | Value |
|---|---|
| ID | E015_log_flush |
| Category | CONTROL.log_flush pulse |
| Goal | Pulse log_flush after queueing 5 entries and confirm the log FIFO drains to empty. |

**Setup**

- Send 5 single-byte commands, wait until rdusedw = 20.

**Stimulus sequence**

1. Read LOG_STATUS (expect rdusedw=20, rdempty=0).
2. AVMM write CONTROL = 0x00000002 (log_flush W1P).
3. Poll LOG_STATUS until rdempty=1 or max 512 mm_clk cycles.
4. Read LOG_POP once.
5. Send a new command. Read LOG_STATUS.

**Expected result**

1. Within the wait window, rdempty asserts and rdusedw goes to 0.
2. LOG_POP returns 0x00000000 (empty-read policy).
3. The next queued command appears as 4 fresh sub-words starting from a known-good rdusedw=4 state.
4. No RX_CMD_COUNT change caused by the flush itself.

**Coverage bins hit**

- `cov_csr.control_writeable_bits[bit1]`

**Pass criteria**

- FIFO drains fully; next command queues cleanly.

**Status:** planned

---

## E016_rx_err_count_increment

| Field | Value |
|---|---|
| ID | E016_rx_err_count_increment |
| Category | Synclink parity error single-shot |
| Goal | Inject exactly one parity error byte and confirm RX_ERR_COUNT increments by 1 with no side effects on the datapath. |

**Setup**

- Reset. RX_ERR_COUNT read and confirmed 0.

**Stimulus sequence**

1. Drive synclink with one byte: data=0x11, error[1]=1 (parity) for a single `lvdspll_clk` cycle.
2. Hold synclink idle for 16 cycles.
3. Read RX_ERR_COUNT, RX_CMD_COUNT, STATUS.
4. Send a clean 0x11 command and observe normal flow.

**Expected result**

1. RX_ERR_COUNT = 1.
2. RX_CMD_COUNT = 0 after step 3.
3. STATUS.recv_idle=1; no runctl beat observed; no log entry from the errored byte.
4. After step 4, RX_CMD_COUNT = 1; log entry present for that clean command.

**Coverage bins hit**

- (error counter is covered by R-series; this edge just closes the single-error boundary)

**Pass criteria**

- Exactly +1 on RX_ERR_COUNT; datapath still healthy.

**Status:** planned

---

## E017_unknown_command

| Field | Value |
|---|---|
| ID | E017_unknown_command |
| Category | Undefined command byte |
| Goal | Send byte 0x77 (undefined) and confirm RTL policy: no runctl fanout, no log entry, no upload ack, no counter corruption. |

**Setup**

- Reset, RX_CMD_COUNT=0, RX_ERR_COUNT=0.

**Stimulus sequence**

1. Send one byte: data=0x77, error=000 (clean).
2. Wait 32 `lvdspll_clk` cycles.
3. Read RX_CMD_COUNT, RX_ERR_COUNT, LOG_STATUS, LAST_CMD.
4. Send one clean CMD_RUN_SYNC (0x11). Check it is processed normally.

**Expected result**

1. Zero runctl beats after step 1.
2. LOG_STATUS.rdempty=1 (no log entry for 0x77).
3. LAST_CMD[7:0] unchanged (0x00).
4. RTL policy: either RX_ERR_COUNT increments by 1 or a dedicated unknown counter captures it; no corruption of RX_CMD_COUNT.
5. Step 4 command processes normally and updates LAST_CMD=0x11.

**Coverage bins hit**

- `cov_cmd.cmd_byte_unknown`

**Pass criteria**

- FSM returns to IDLE cleanly; only clean command mutates LAST_CMD.

**Status:** planned

---

## E018_atomic_gts_two_readers

| Field | Value |
|---|---|
| ID | E018_atomic_gts_two_readers |
| Category | Atomic GTS_L/GTS_H snapshot race |
| Goal | With gts counter free-running at 125 MHz, issue two interleaved GTS_L/GTS_H AVMM read pairs from the mm_clk side and confirm each pair is internally consistent (no torn 48-bit value). |

**Setup**

- mm_clk = 156.25 MHz, lvdspll_clk = 125 MHz, async, free phase.
- gts counter advancing.

**Stimulus sequence**

1. AVMM read GTS_L (0x0D); call the result L1.
2. AVMM read GTS_L again; call the result L2 (second reader starts before first reader reads H).
3. AVMM read GTS_H (0x0E); call this H_after_L2 (hardware latches H on each GTS_L read; last latch wins).
4. Repeat the pattern several hundred times with varied delays between reads (0, 1, 2 mm_clk cycles) to sweep the async phase.

**Expected result**

1. The semantics per section 3: GTS_H always corresponds to the most recent GTS_L read. The last-written L into the CSR register (L2) must be paired with the H captured at that read's sample instant.
2. Across all iterations, the pair (L2, H_after_L2) represents a monotonically non-decreasing 48-bit value (allowing wrap at 48 bits).
3. No pair where H_after_L2's upper carry implies an epoch inconsistent with L2 (i.e. no torn 48-bit value).
4. Scoreboard compares against the known-good gts model.

**Coverage bins hit**

- `cov_csr.csr_addr_read[0x0D], [0x0E]`
- C3 (CSR read during any recv state)

**Pass criteria**

- Zero torn pairs across all iterations and phase offsets.

**Status:** planned

---

## E019_status_state_encoding

| Field | Value |
|---|---|
| ID | E019_status_state_encoding |
| Category | STATUS.recv_state_enc mid-command |
| Goal | Stall the recv FSM in RX_PAYLOAD by withholding the next synclink byte, then read STATUS from mm_clk and confirm `recv_state_enc[15:8]` matches the RX_PAYLOAD encoding. |

**Setup**

- Reset. CSR idle. Default clock ratio.

**Stimulus sequence**

1. Send CMD_RUN_PREPARE (0x10) header byte with valid=1, then hold `synclink.valid=0` before the first payload byte.
2. Wait 16 `lvdspll_clk` cycles.
3. Read STATUS. Record recv_state_enc.
4. Resume synclink and send the remaining 4 payload bytes.
5. Read STATUS again after completion.

**Expected result**

1. STATUS at step 3: recv_idle=0, host_idle=1 (host FSM still idle because nothing posted yet), recv_state_enc = RX_PAYLOAD encoding.
2. STATUS at step 5: recv_idle=1, host_idle=1, recv_state_enc = IDLE encoding.
3. The command completes normally after resume; RUN_NUMBER updates; log entry present.

**Coverage bins hit**

- `cov_cross.C3[csr_read x recv_state=RX_PAYLOAD]`
- `cov_cmd.cmd_byte_synclink[0x10]`

**Pass criteria**

- recv_state_enc matches the RX_PAYLOAD encoding exactly.

**Status:** planned

---

## E020_runctl_ready_max_latency

| Field | Value |
|---|---|
| ID | E020_runctl_ready_max_latency |
| Category | Max ready latency stress |
| Goal | Apply the maximum supported `runctl_ready` latency (harness-defined, typically 1023 `lvdspll_clk` cycles) and confirm all commands eventually drain with no FSM hang. |

**Setup**

- `runctl_sink_agent` configured for fixed ready latency = MAX.
- Upload ready free.

**Stimulus sequence**

1. Send 8 mixed single-byte commands back-to-back on synclink.
2. Watch recv/host FSM state via STATUS polling.
3. Wait until STATUS.recv_idle=1 and STATUS.host_idle=1, with a watchdog of `8 * (MAX + 32)` lvdspll_clk cycles.
4. Read RX_CMD_COUNT and LOG_STATUS.rdusedw.

**Expected result**

1. Every command handshakes after MAX-cycle latency each; no FSM ever hangs.
2. RX_CMD_COUNT = 8.
3. 32 log sub-words queued.
4. recv_state_enc and host_state_enc cycle through POSTING/IDLE exactly 8 times each.
5. Watchdog never fires.

**Coverage bins hit**

- `cov_cross.C2[latency=max x state=POSTING]`

**Pass criteria**

- All 8 drained, bounded by the watchdog.

**Status:** planned

---

## Expanded E-case table (E021-E100)

The cases below extend the directed E-bucket to cover the frozen RTL decisions enumerated in the authoring brief: LOCAL_CMD waitrequest stall, log FIFO drop-new + log_drop saturation, soft_reset / log_flush interleavings against all recv/host states, counter saturation at 0xFFFF_FFFF, CDC phase sweep of mm_clk vs lvdspll_clk, 48-bit GTS wrap with atomic snapshot, 4x2 reset-mask truth table, payload boundary values, back-to-back command streams, mixed-command round-robin, state-encoding observation, local_cmd vs synclink priority, META selector masking, FPGA_ADDRESS stickiness, hard-reset launch timing, log sub-word ordering, and CSR waitrequest release timing.

Each row is self-contained (stimulus + expected in 1-2 sentences). Every case tests a single condition frozen in `rtl/runctl_mgmt_host.sv`; no behaviors outside the frozen-decisions list are introduced. All counts below use sub-word units (4 per command) for log FIFO depth and cycle units of `lvdspll_clk` for lvds-side timing or `mm_clk` for mm-side timing as noted.

| ID | Category | Stimulus | Expected |
|----|----------|----------|----------|
| E021_runctl_ready_low_1 | runctl backpressure | Send CMD_RUN_SYNC (0x11); hold `runctl_ready=0` for 1 lvdspll cycle after first `valid`, then release. | Handshake completes on cycle 2; RX_CMD_COUNT+=1; host FSM observed in HOST_POSTING (0x01) for exactly 1 cycle. |
| E022_runctl_ready_low_16 | runctl backpressure | Send 0x11; hold `runctl_ready=0` for 16 lvdspll cycles then release. | Valid stable for 16 cycles; exactly one beat at cycle 17; RX_CMD_COUNT+=1; no duplicate beats. |
| E023_runctl_ready_low_256 | runctl backpressure | Send 0x11; hold `runctl_ready=0` for 256 lvdspll cycles then release. | Same as E022 but over 256-cycle window; no FSM hang; recv_state_enc=RECV_LOGGING or RECV_CLEANUP observable via STATUS during stall. |
| E024_runctl_ready_low_1024 | runctl backpressure | Send 0x11; hold `runctl_ready=0` for 1024 lvdspll cycles. | One beat on release; watchdog `> 1024+32` cycles; no log entry loss. |
| E025_runctl_ready_low_10000 | runctl backpressure | Send 0x11; hold `runctl_ready=0` for 10000 lvdspll cycles. | One beat on release; no SVA firings; log_drop_count unchanged (log FIFO capacity unused). |
| E026_upload_ready_low_1 | upload backpressure | Send CMD_RUN_PREPARE 0x10 + 4B run_number=0x1; hold `upload_ready=0` for 1 cycle after `upload_valid` then release. | Exactly one ack packet (sop+eop), data[35:32] k-flag = RUN_START_ACK_SYMBOL (0xFE). |
| E027_upload_ready_low_16 | upload backpressure | Same as E026 with 16-cycle hold. | Exactly one ack packet; upload FSM stable during stall. |
| E028_upload_ready_low_64 | upload backpressure | Same with 64-cycle hold. | Single ack on release; RUN_NUMBER CSR updated. |
| E029_upload_ready_low_256 | upload backpressure | Same with 256-cycle hold. | Single ack; no duplicate sop/eop; log entry present. |
| E030_upload_ready_low_1024 | upload backpressure | Same with 1024-cycle hold. | Single ack; host/recv FSMs return to idle post-drain. |
| E031_upload_ready_low_10000 | upload backpressure | Same with 10000-cycle hold. | Single ack; no SVA firings; no FSM hang. |
| E032_upload_ready_low_end_run | upload backpressure | Send CMD_END_RUN (0x13); hold upload_ready=0 for 1024 cycles then release. | Exactly one ack packet with k-flag = RUN_END_ACK_SYMBOL (0xFD); runctl also emits 0x13 beat once runctl_ready high. |
| E033_log_fifo_rdusedw_1 | log FIFO near-empty | From empty, push exactly one 1-byte command that produces 4 sub-words then LOG_POP x3. | After pop x3, LOG_STATUS.rdusedw=1, rdempty=0; pop once more -> rdempty=1. |
| E034_log_fifo_rdusedw_2 | log FIFO near-empty | Drive state to rdusedw=2 via push+partial-pop sequence; read LOG_STATUS. | rdusedw=2 observed; subsequent two LOG_POPs return correct sub-words in FIFO order. |
| E035_log_fifo_rdusedw_63 | log FIFO boundary | Push 16 commands (64 sub-words) and LOG_POP once to reach rdusedw=63. | LOG_STATUS.rdusedw=63, rdempty=0, rdfull=0. |
| E036_log_fifo_rdusedw_64 | log FIFO boundary | Push exactly 16 single-byte commands (64 sub-words) from empty without popping. | rdusedw=64, rdempty=0; scoreboard agrees. |
| E037_log_fifo_rdusedw_128 | log FIFO mid-depth | Push 32 commands (128 sub-words) without popping. | rdusedw=128. |
| E038_log_fifo_rdusedw_255 | log FIFO near-full inner | Push 64 commands and pop once to reach rdusedw=255. | rdusedw=255, rdfull=0. |
| E039_log_fifo_rdusedw_256 | log FIFO wrap | Push 64 commands exactly (256 sub-words) without popping. | rdusedw=256; scoreboard agrees; no drops (assumed read-depth>=256). |
| E040_log_fifo_rdusedw_512 | log FIFO half-full | Push 128 commands (512 sub-words) without popping. | rdusedw=512; log_drop_count unchanged. |
| E041_log_fifo_rdusedw_1023 | log FIFO near-full outer | Push commands until rdusedw=1023. | LOG_STATUS.rdusedw=1023, rdfull=0. |
| E042_log_fifo_rdusedw_1024 | log FIFO full | Push one more command to reach rdusedw=1024 (full). | rdusedw=1024, rdfull=1; log_drop_count=0 (no overflow yet). |
| E043_log_fifo_overflow_drop1 | log FIFO drop-new +1 | From E042 full state, push one more command while `wrfull=1`. | Command still fans out on runctl (RX_CMD_COUNT+=1); log_drop_count increments by exactly 1; no torn entry. |
| E044_log_fifo_overflow_drop5 | log FIFO drop-new +5 | From E042 full state, push 5 more commands. | log_drop_count increments by exactly 5; rdusedw stays at max; RX_CMD_COUNT accounts for all 5 on runctl. |
| E045_log_drop_saturate | log_drop saturation | Force log_drop_count to 0xFFFF_FFFE, push 1 more drop, read; then push 2 more drops and read. | First read=0xFFFF_FFFF; after 2 more drops, read still=0xFFFF_FFFF (saturating, no wrap). |
| E046_rx_cmd_count_saturate | RX_CMD_COUNT saturation | Stream commands until RX_CMD_COUNT=0xFFFF_FFFE, send one more, read. Send one more, read again. | First read=0xFFFF_FFFF; second read still 0xFFFF_FFFF; datapath still fans out. |
| E047_rx_err_count_saturate | RX_ERR_COUNT saturation | Inject parity errors until RX_ERR_COUNT=0xFFFF_FFFE, inject one more, read. Inject one more, read. | Same saturation behavior as E046. |
| E048_cdc_ratio_0p5 | CDC phase sweep | Set mm_clk/lvdspll ratio 0.5x (mm_clk=62.5 MHz, lvds=125 MHz); stream 32 mixed commands; poll CSR. | Scoreboard model agrees on RX_CMD_COUNT, GTS, and STATUS readbacks; 2-3 mm_clk lag tolerated on gray-code CDC. |
| E049_cdc_ratio_0p9 | CDC phase sweep | mm=112.5 MHz, lvds=125 MHz; 32 mixed commands. | Same scoreboard agreement; no torn GTS snapshot. |
| E050_cdc_ratio_1p0 | CDC phase sweep | mm=125 MHz, lvds=125 MHz (same rate, async phase). | Scoreboard agreement; STATUS.local_cmd_busy behaves as in E013. |
| E051_cdc_ratio_1p1 | CDC phase sweep | mm=137.5 MHz, lvds=125 MHz; 32 mixed commands. | Scoreboard agreement; no FSM hang. |
| E052_cdc_ratio_2x | CDC phase sweep | mm=250 MHz, lvds=125 MHz; 32 mixed commands. | Scoreboard agreement; local_cmd CDC busy-window shrinks but clears within budget. |
| E053_cdc_ratio_3x | CDC phase sweep | mm=375 MHz, lvds=125 MHz; 32 mixed commands. | Scoreboard agreement; 2FF latency still yields consistent reads. |
| E054_gts_wrap_low | GTS low-word wrap | Force lvds counter to 0x0000_0000_FFFF_FFFE; send CMD_RUN_SYNC across the low-word wrap; read GTS_L then GTS_H. | Snapshot pair consistent; GTS_H[47:32] either 0 or 1 matching the instant GTS_L latched; no torn epoch. |
| E055_gts_wrap_full | GTS 48-bit wrap | Force lvds counter to 0xFFFF_FFFF_FFF0; send 4 CMD_RUN_SYNC straddling the 48-bit wrap; read GTS_L/GTS_H three times. | All snapshot pairs consistent with gts model; no pair mixes pre-wrap low with post-wrap high. |
| E056_gts_repeat_l_read | GTS snapshot repeatability | Two rapid AVMM reads of GTS_L with 0, 1, 2 mm_clk gaps between them. | Both reads succeed; waitrequest released each read; pair (L2, subsequent H) consistent. |
| E057_soft_reset_during_rx_idle | soft_reset interleave | Pulse CONTROL.soft_reset while recv_state=RECV_IDLE (0x00). | recv/host return to IDLE; no log entry written; GTS counter unchanged. |
| E058_soft_reset_during_rx_payload | soft_reset interleave | Send 0x10 header then hold valid=0; while recv_state=RECV_RX_PAYLOAD (0x01), pulse soft_reset. | Partial payload discarded; no log entry queued; no upload ack; STATUS.recv_idle=1 post-pulse. |
| E059_soft_reset_during_logging | soft_reset interleave | Stall with runctl_ready=0 long enough to observe recv_state=RECV_LOGGING (0x02); pulse soft_reset. | recv returns to IDLE; partial log entry discarded; no torn entry; log_drop_count unchanged. |
| E060_soft_reset_during_log_error | soft_reset interleave | Inject parity error to force recv_state=RECV_LOG_ERROR (0x03); pulse soft_reset same cycle. | recv returns to IDLE; RX_ERR_COUNT increment still coherent; no spurious runctl beat. |
| E061_soft_reset_during_cleanup | soft_reset interleave | Drive recv_state=RECV_CLEANUP (0x04) via a completed command; pulse soft_reset mid-cleanup. | recv returns to IDLE; FSMs clean; next command processes normally. |
| E062_soft_reset_gts_preserved | soft_reset GTS rule | Let GTS advance; pulse soft_reset; read GTS_L/GTS_H 8 mm_clk later. | GTS reading is higher than pre-pulse reading (GTS counter NOT reset by soft_reset). |
| E063_log_flush_during_write | log_flush interleave | Inject synclink command so log write is in progress on lvds side, simultaneously pulse CONTROL.log_flush on mm side. | Drain completes cleanly; either full entry present or fully absent; LOG_STATUS.rdempty=1 when drain done. |
| E064_log_flush_idle_repeat | log_flush interleave | Pulse log_flush on an already-empty FIFO. | No side effects; rdempty stays 1; rdusedw=0. |
| E065_mask_00_reset | reset mask matrix | CONTROL[5:4]=2'b00, send CMD_RESET (0x30) mask=0x00FF. | dp_hard_reset=1 and ct_hard_reset=1; RESET_MASK[15:0]=0x00FF. |
| E066_mask_01_reset | reset mask matrix | CONTROL[5:4]=2'b01 (rst_mask_dp=1), send CMD_RESET mask=0x0F0F. | dp_hard_reset=0, ct_hard_reset=1; RESET_MASK updated. |
| E067_mask_10_reset | reset mask matrix | CONTROL[5:4]=2'b10 (rst_mask_ct=1), send CMD_RESET mask=0xF0F0. | dp_hard_reset=1, ct_hard_reset=0. |
| E068_mask_11_reset | reset mask matrix | CONTROL[5:4]=2'b11, send CMD_RESET mask=0xFFFF. | dp_hard_reset=0, ct_hard_reset=0; RESET_MASK=0xFFFF. |
| E069_mask_00_stop_reset | reset mask matrix | CONTROL[5:4]=2'b00, send CMD_STOP_RESET (0x31) mask=0x00FF. | Both dp/ct_hard_reset deasserted; RESET_MASK[31:16]=0x00FF. |
| E070_mask_01_stop_reset | reset mask matrix | CONTROL[5:4]=2'b01, send CMD_STOP_RESET mask=0x0F0F. | dp deasserts, ct_hard_reset path suppressed (dp_mask=1 means dp does NOT assert on reset; STOP_RESET drives ct path). Verify truth-table row. |
| E071_mask_10_stop_reset | reset mask matrix | CONTROL[5:4]=2'b10, send CMD_STOP_RESET mask=0xF0F0. | Symmetric row. |
| E072_mask_11_stop_reset | reset mask matrix | CONTROL[5:4]=2'b11, send CMD_STOP_RESET mask=0xFFFF. | Both outputs stay deasserted; RESET_MASK[31:16]=0xFFFF. |
| E073_runprep_zero | payload boundary | Send CMD_RUN_PREPARE, run_number=0x0000_0000. | RUN_NUMBER=0, ack packet emitted, log payload sub-word=0. |
| E074_runprep_one | payload boundary | Send CMD_RUN_PREPARE, run_number=0x0000_0001. | RUN_NUMBER=1; ack emitted. |
| E075_runprep_max | payload boundary | Send CMD_RUN_PREPARE, run_number=0xFFFF_FFFF. | RUN_NUMBER=0xFFFF_FFFF; shift register `recv_payload32` exactly filled (32b). |
| E076_runprep_msb | payload boundary | Send CMD_RUN_PREPARE, run_number=0x8000_0000. | RUN_NUMBER=0x8000_0000 (MSB walk). |
| E077_reset_mask_0000 | payload boundary | Send CMD_RESET mask=0x0000. | RESET_MASK[15:0]=0; dp/ct both assert per mask (all bits clear). |
| E078_reset_mask_0001 | payload boundary | Send CMD_RESET mask=0x0001. | RESET_MASK[15:0]=0x0001. |
| E079_reset_mask_8000 | payload boundary | Send CMD_RESET mask=0x8000. | RESET_MASK[15:0]=0x8000. |
| E080_reset_mask_ffff | payload boundary | Send CMD_RESET mask=0xFFFF. | RESET_MASK[15:0]=0xFFFF. |
| E081_address_0000 | payload boundary | Send CMD_ADDRESS (0x40) addr=0x0000. | FPGA_ADDRESS[15:0]=0x0000, [31]=1 sticky; zero runctl beats. |
| E082_address_ffff | payload boundary | Send CMD_ADDRESS addr=0xFFFF. | FPGA_ADDRESS[15:0]=0xFFFF, [31]=1. |
| E083_b2b_1 | back-to-back stream | Stream 1 x CMD_RUN_SYNC back-to-back. | RX_CMD_COUNT delta=1; 4 log sub-words. |
| E084_b2b_2 | back-to-back stream | Stream 2 x 0x11. | delta=2; 8 sub-words. |
| E085_b2b_4 | back-to-back stream | Stream 4 x 0x11. | delta=4; 16 sub-words. |
| E086_b2b_8 | back-to-back stream | Stream 8 x 0x11. | delta=8; 32 sub-words. |
| E087_b2b_32 | back-to-back stream | Stream 32 x 0x11. | delta=32; 128 sub-words. |
| E088_b2b_64 | back-to-back stream | Stream 64 x 0x11. | delta=64; 256 sub-words. |
| E089_b2b_128 | back-to-back stream | Stream 128 x 0x11 with continuous runctl_ready. | delta=128; 512 sub-words; no drops. |
| E090_b2b_256 | back-to-back stream | Stream 256 x 0x11. | delta=256; 1024 sub-words -> rdusedw hits full boundary; log_drop_count=0. |
| E091_mixed_rr_10 | mixed round-robin | Round-robin through all 10 command bytes {0x10,0x11,0x12,0x13,0x14,0x30,0x31,0x32,0x33,0x40} once (10 total, payloads from LCG PRNG). | RX_CMD_COUNT+=10 (or 9 if ADDRESS is counted separately in RTL, verify); log entries for each; 2 upload acks (0x10,0x13); zero runctl beats for 0x40 only. |
| E092_mixed_rr_100 | mixed round-robin | Round-robin all 10 bytes x 10 iterations = 100 commands. | RX_CMD_COUNT delta=100; scoreboard agrees on all runctl beats and ack packets; log entries match. |
| E093_mixed_rr_1000 | mixed round-robin | Round-robin all 10 bytes x 100 iterations = 1000 commands. | RX_CMD_COUNT delta=1000; log FIFO drained concurrently to avoid overflow; 200 upload acks (100 RUN_PREPARE + 100 END_RUN). |
| E094_recv_state_enc_sweep | STATUS encoding | Park recv FSM in each of {IDLE=0x00, RX_PAYLOAD=0x01, LOGGING=0x02, LOG_ERROR=0x03, CLEANUP=0x04}; read STATUS[15:8]. | Exact 8-bit encoding observed per state as listed. |
| E095_host_state_enc_sweep | STATUS encoding | Park host FSM in each of {IDLE=0x00, POSTING=0x01, CLEANUP=0x02}; read STATUS[23:16]. | Exact 8-bit encoding per state. |
| E096_local_cmd_vs_synclink_prio | local_cmd priority | Drive a synclink valid byte and a local_cmd_pending_lvds toggle arriving on the same lvdspll cycle when recv is in RECV_IDLE. | local_cmd wins (local_cmd fans out first); synclink byte stalls back one cycle and still processes; RX_CMD_COUNT+=2 in local-then-synclink order. |
| E097_local_cmd_busy_timing | local_cmd timing | Write LOCAL_CMD (0x13) then read STATUS on the very next mm_clk cycle; poll STATUS.local_cmd_busy until clear. | bit[30] asserted within 1 mm_clk of the write completion; clears within CDC round-trip budget (~6 mm_clk cycles typical). Current direct reproducer for the held-write subcase: `runctl_mgmt_host_local_cmd_backpressure_test` (`BUG-001-R`). |
| E098_csr_waitrequest_release | CSR waitrequest | Issue LOCAL_CMD write stall scenario: second write lands while busy=1 and `avs_csr_waitrequest=1`. Observe release timing. | Waitrequest releases exactly 1 mm_clk cycle after local_cmd_busy clears; second write then completes; scoreboard sees correct serialization. |
| E099_meta_sel_boundary | META selector | Write META=0 read; write META=1 read; write META=2 read; write META=3 read; write META=0xFFFF_FFFC read; write META=0x00000005 read. | Reads 1,2,3,4 return pages 0,1,2,3; read 5 returns page 0 (lower 2 bits of 0xFFFF_FFFC = 00); read 6 returns page 1 (lower 2 bits of 0x05 = 01). |
| E100_fpga_address_sticky | sticky valid | Send CMD_ADDRESS addr=0x1111; then send 10 other commands (mixture excluding 0x40); read FPGA_ADDRESS each time. | After every intermediate command, FPGA_ADDRESS[15:0]=0x1111 and [31]=1 sticky-valid, unchanged by other commands. |
| E101_hard_reset_launch_timing | hard-reset launch | Send CMD_RESET mask=0x0001 with both masks clear; measure lvdspll cycles between `pipe_r2h_done` edge and dp_hard_reset rising edge (and same for ct_hard_reset and CMD_STOP_RESET). | Both outputs toggle within 1-2 lvdspll cycles of `pipe_r2h_done`; scoreboard records the fixed launch latency for regression. |
| E102_log_subword_order_runprep | log sub-word order | Send CMD_RUN_PREPARE run_number=0xA5A5_A5A5; LOG_POP 4 sub-words. | Sub-word 0 = recv_ts[47:16]; sub-word 1 = {recv_ts[15:0], 8'h00, 8'h10}; sub-word 2 = 0xA5A5_A5A5; sub-word 3 = exec_ts[31:0]; all in strict pop order. |

Total E-cases after this extension: E001-E020 (20 existing) + E021-E102 (82 new) = 102 cases.

---

## Plan drift notes

DV_PLAN.md section 6.2 originally defined E001-E020 only. The scope reminder in this DV_EDGE authoring brief lists several boundary categories that now have matching IDs in the extended table above (E021-E102). These are recorded here as the original gaps; see the extended table for coverage.

| Gap category | Condition not covered by E001-E020 | Suggested future E-ID range |
|---|---|---|
| CDC phase sweep mm_clk vs lvdspll_clk | E018 sweeps phases for GTS snapshot only. A dedicated test that varies the mm/lvdspll frequency ratio across {100/125, 125/125, 156.25/125, 200/125 MHz} and forces CSR activity to straddle every toggle-handshake CDC path (local_cmd, status snapshot, STATUS.dp_hard_reset, STATUS.ct_hard_reset) is not in the plan. | E021 candidate |
| SCRATCH alternating patterns | Covered by `cov_csr.scratch_pattern` via X015 (cross bucket), but no E-bucket case forces the 0x00000000 <-> 0xFFFFFFFF <-> 0xAAAAAAAA <-> 0x55555555 pattern set in isolation with a CSR readback assertion on every transition. | E022 candidate |
| soft_reset mid-posting | E014 covers soft_reset while idle. soft_reset asserted on the exact mm_clk cycle that the recv FSM transitions IDLE->POSTING is not enumerated (R009 in DV_ERROR covers general mid-command soft_reset but not the exact POSTING-entry edge). | E023 candidate |
| lvdspll_reset during upload ack emission | R013 covers upload ready stuck; an edge case that deasserts lvdspll_reset on the same cycle `upload_valid` first asserts is not in the plan. | E024 candidate |
| Simultaneous synclink byte and LOCAL_CMD write | Toggle-handshake race when the mm_clk LOCAL_CMD write and the `lvdspll_clk` synclink byte latch in the same real-time instant. X003 covers ordering but not the deliberately simultaneous submission. | E025 candidate |
| CMD_ADDRESS vs CMD_RESET ordering race | E011 covers CMD_ADDRESS fanout suppression, E007-E009 cover CMD_RESET masks; the ordering case "CMD_ADDRESS then CMD_RESET in the same back-to-back pair with no idle gap" is not enumerated. | E026 candidate |
| rst_mask changed between RESET and STOP_RESET | E007-E009 hold the masks constant across the reset pair. A case where CONTROL is rewritten between the assert and release commands is not enumerated. | E027 candidate |
| Log FIFO near-empty boundary (rdusedw=1) | E005 pops from a near-full state down to empty; a case that holds `rdusedw` at exactly 1 sub-word and pops it is not in the plan. | E028 candidate |
| mm_reset during CSR access in flight | R008 covers mm_reset mid-command; an edge case that asserts mm_reset in the exact mm_clk cycle that a LOG_POP read completes is not enumerated. | E029 candidate |

These gaps are recommended for the next DV_PLAN revision. No implementation is planned for them under the current plan.
