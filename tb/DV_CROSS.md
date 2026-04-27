# DV Cross — runctl_mgmt_host

**Companion docs:** `README.md`, `DV_PLAN.md`, `DV_HARNESS.md`,
`DV_BASIC.md`, `DV_EDGE.md`, `DV_ERROR.md`, `DV_PROF.md`,
`BUG_HISTORY.md`

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**DUT:** `runctl_mgmt_host`
**Canonical ID Space:** X001 – X015 (from DV_PLAN.md section 6.3)
**Date:** 2026-04-13
**Status:** Planning. Every X-ID below is `planned`.

This file expands each X-test in `DV_PLAN.md` into an executable card and pins
every card to the cross-coverage cells it is required to hit. The traceability
table in section 4 is the single source the signoff review uses to prove 100%
cross coverage (102 cells across 7 axes).

---

## 0. Conventions

- **Transaction**: one complete scenario — inject synclink/local stimulus,
  drive CSR traffic, manipulate backpressure, sample coverage collectors on
  monitor hooks. DUT is reset only when the test explicitly asks for it.
- **Sampling point**: `runctl_mgmt_cov` counter-collector hooks fire on the
  scoreboard's "transaction complete" signal for command-class bins, on every
  CSR beat for CSR-class bins, on every `log_wr_en` / `log_rd_en` for log bins,
  and on every `runctl_ready` / `upload_ready` sample for backpressure bins.
- **Pattern names** (must match `DV_HARNESS.md` when it lands — proposed here):
  - `always-ready` — ready held 1'b1 for the entire test.
  - `1-clk-stutter` — ready toggles 1/0 every cycle (50% duty).
  - `8-clk-hold` — ready=0 for 8 cycles then =1 for 8 cycles (stream/hold).
  - `random-LCG` — ready driven by `mutrig_common_pkg::lcg_next` threshold,
    50% density by default, seeded from `+SEED=`.
  - `held-low` — ready=0 for ≥N cycles then released (N is per-test).
  - `toggled` — same as `1-clk-stutter` when used as an upload backpressure
    class; retained as an alias because DV_PLAN section 5 C1 uses "toggled".
  - `continuous-ready` — DV_PLAN C1 alias for `always-ready`.
- **Coverage axes** (re-stated from DV_PLAN.md §5.3, verbatim cardinalities):
  - `C1` — synclink cmd class (10) × upload backpressure (3) = 30 cells
  - `C2` — runctl ready latency (4) × recv_state stall in POSTING (1) = 4 cells
  - `C3` — CSR activity class (3) × recv_state (4) = 12 cells
  - `C4` — log FIFO occupancy bin (5) × LOG_POP burst length (3) = 15 cells
  - `C5` — rst_mask combo (4) × reset cmd class (2) = 8 cells
  - `C6` — lvdspll_reset × mm_reset ordering (3) = 3 cells
  - `C7` — local_cmd submit phase (3) × command class (10) = 30 cells
  - **Total: 102 cross cells.**
- **Minimum-axes rule**: every X-test covers ≥2 cross axes. Tests that only
  hit one axis belong in `DV_EDGE.md`. Each card states the axes explicitly.
- **Cell notation**: `C<n>[axis_a_value × axis_b_value]`, e.g.
  `C1[RUN_PREPARE × toggled]`, `C7[local_cmd@POSTING × ABORT_RUN]`.

Command class shorthand used in cell lists:
`RP=RUN_PREPARE(0x10)`, `RS=RUN_SYNC(0x11)`, `ST=START_RUN(0x12)`,
`ER=END_RUN(0x13)`, `AB=ABORT_RUN(0x14)`, `RST=CMD_RESET(0x30)`,
`SRST=CMD_STOP_RESET(0x31)`, `EN=ENABLE(0x32)`, `DI=DISABLE(0x33)`,
`AD=ADDRESS(0x40)`. These ten symbols enumerate the 10-wide axis used by
C1 and C7.

---

## 1. Coverage-closure strategy

- C1 (30 cells) and C7 (30 cells) are the largest axes. They are swept as
  matrices in X006 and X011 respectively; other tests only opportunistically
  add hits.
- C4 (15 cells) is swept in X005 as the dedicated fill/drain test. X013
  additionally touches the `(empty|low) × burst=16` edges that X005 must not
  be relied on to cover because its fill controller is probabilistic.
- C2 (4 cells) is swept by X007. The single-cell `recv_state=POSTING` dimension
  is enforced by withholding the next synclink byte during POSTING.
- C3 (12 cells) is distributed: X001 covers the `read × *` row, X002 covers
  the `write × *` row, X014 / X015 reinforce `write × RX_PAYLOAD` and
  `write × POSTING`, and the `idle × *` row is hit implicitly at test start
  before stimulus begins. X012 guarantees the full matrix as a long run.
- C5 (8 cells) is swept by X004.
- C6 (3 cells) is swept by X008 / X009 / X010, one cell each.

---

## 2. X-test cards

### X001 — csr_traffic_during_cmd

| Field | Detail |
|-------|--------|
| **Category** | CSR × recv-state mix |
| **Axes covered** | C3 (primary), C1 (secondary), C7 (incidental) |
| **Goal** | Prove CSR read traffic to STATUS / RECV_TS / LAST_CMD is atomic and non-intrusive while every recv_state value is visited. Closes the `read × {IDLE, RX_PAYLOAD, POSTING, LOG_WR}` row of C3 (4 cells). |
| **Setup** | Default CSRs. runctl_sink = `8-clk-hold` so the host FSM visibly enters POSTING. upload_sink = `always-ready`. log FIFO initialised empty. |
| **Stimulus** | 1. Seed LCG, kick CSR agent into a continuous read-only loop that round-robins STATUS (0x03) → RECV_TS_L (0x09) → RECV_TS_H (0x0A) → LAST_CMD (0x04) with 0..3-cycle idle gaps. 2. Inject a 32-command stream on synclink covering every command class at least once (use the 10-symbol class set). 3. Withhold one synclink byte mid-payload for two of the commands to force RX_PAYLOAD sampling. 4. After the stream, drain log FIFO via 4 LOG_POP reads per command. |
| **Expected** | 1. Every CSR read completes in 1 mm_clk with scoreboard-matched data. 2. No command is dropped; RX_CMD_COUNT equals the issued count. 3. Scoreboard sees recv_state ∈ {IDLE, RX_PAYLOAD, POSTING, LOG_WR} at ≥1 CSR-read sample each. 4. No SVA firings. |
| **Cells hit** | C3[read×IDLE], C3[read×RX_PAYLOAD], C3[read×POSTING], C3[read×LOG_WR]; C1[{RP,RS,ST,ER,AB,RST,SRST,EN,DI,AD} × continuous-ready]; C7[IDLE × *] for any command issued while recv was idle. |
| **Pass** | 100% of C3 read-row cells hit; no scoreboard / SVA errors; CSR shadow consistent. |
| **Status** | planned |

### X002 — csr_writes_during_cmd

| Field | Detail |
|-------|--------|
| **Category** | CSR × recv-state mix (write side) |
| **Axes covered** | C3 (primary), C1 (secondary) |
| **Goal** | Prove write traffic to SCRATCH / CONTROL does not interfere with the recv or host FSMs. Closes the `write × *` row of C3 (4 cells). |
| **Setup** | runctl_sink = `random-LCG` at 50%. upload_sink = `always-ready`. CONTROL rst_masks start at 00. |
| **Stimulus** | 1. Launch CSR agent in write-only mode: SCRATCH=LCG pattern, CONTROL bit-twiddles on rst_mask_dp/rst_mask_ct (not on soft_reset/log_flush). 2. Inject 20 synclink commands spanning all classes except 0x30/0x31 (to avoid confounding CONTROL mask reads). 3. Deliberately time 4 writes to land while recv is in RX_PAYLOAD and 4 more while in POSTING (monitor feedback via recv_state_enc). |
| **Expected** | 1. All 20 commands delivered. 2. CSR shadow agrees after each write. 3. rst_mask_dp/ct never corrupts the in-flight command path (no spurious dp/ct_hard_reset). |
| **Cells hit** | C3[write×IDLE], C3[write×RX_PAYLOAD], C3[write×POSTING], C3[write×LOG_WR]; C1[{RP,RS,ST,ER,AB,EN,DI,AD} × continuous-ready]. |
| **Pass** | C3 write-row 4/4 cells hit; no interference. |
| **Status** | planned |

### X003 — local_cmd_vs_synclink

| Field | Detail |
|-------|--------|
| **Category** | Injection-path contention |
| **Axes covered** | C7 (primary), C1 (secondary), C3 (incidental) |
| **Goal** | Verify the arbitration between `local_cmd` (mm_clk submit, toggle-handshake CDC) and `synclink` (lvdspll_clk stream) serialises into one recv pipeline without loss or reordering-beyond-spec. |
| **Setup** | Default CSRs. runctl_sink = `always-ready`. upload_sink = `always-ready`. |
| **Stimulus** | 1. Start a slow synclink command (CMD_RESET with 16-bit payload) and stall one payload byte via AVST valid deassertion so recv stays in RX_PAYLOAD. 2. Issue a LOCAL_CMD write of RUN_SYNC (0x11000000) from the CSR side. 3. Poll STATUS.local_cmd_busy, wait for release, then submit ABORT_RUN (0x14000000) via LOCAL_CMD. 4. Release the stalled synclink byte; let both drain. 5. Repeat the sequence with recv in POSTING (hold runctl_ready=0 for 32 cycles). |
| **Expected** | 1. Both synclink and local commands reach the host FSM in an order consistent with the reference model. 2. STATUS.local_cmd_busy is asserted while the toggle handshake is in flight and never drops `local_cmd` writes that were accepted by the mm side. 3. Log FIFO records all commands. |
| **Cells hit** | C7[RX_PAYLOAD × RS], C7[RX_PAYLOAD × AB], C7[POSTING × RS], C7[POSTING × AB]; C1[RST × continuous-ready]; C3[write × RX_PAYLOAD], C3[write × POSTING] (the LOCAL_CMD write is a CSR write). |
| **Pass** | ≥4 C7 cells hit, no lost commands, CDC handshake clean (SVA sva_cdc silent). |
| **Status** | planned |

### X004 — mask_combo_sweep

| Field | Detail |
|-------|--------|
| **Category** | rst_mask × reset command cross |
| **Axes covered** | C5 (primary, sweeps full 8-cell matrix), C3 (incidental) |
| **Goal** | Close the full C5 matrix: 4 rst_mask combos × {CMD_RESET, CMD_STOP_RESET}. |
| **Setup** | runctl_sink = `always-ready`. upload_sink = `always-ready`. Start from dp_hard_reset=ct_hard_reset=0. |
| **Stimulus** | For each of the 4 combos {dp=0 ct=0, dp=0 ct=1, dp=1 ct=0, dp=1 ct=1}: 1. Write CONTROL.rst_mask to the combo. 2. Send CMD_RESET (0x30) with assert_mask=0xFFFF. 3. Wait 16 lvdspll cycles. 4. Send CMD_STOP_RESET (0x31) with release_mask=0xFFFF. 5. Wait 16 cycles, read RESET_MASK CSR and dp/ct_hard_reset via STATUS. |
| **Expected** | 1. dp_hard_reset asserts only when rst_mask_dp=0. 2. ct_hard_reset asserts only when rst_mask_ct=0. 3. CMD_STOP_RESET deasserts symmetrically. 4. RESET_MASK CSR always updated regardless of mask. |
| **Cells hit** | C5[00×RST], C5[00×SRST], C5[01×RST], C5[01×SRST], C5[10×RST], C5[10×SRST], C5[11×RST], C5[11×SRST]; C3[write×IDLE] via CONTROL writes. |
| **Pass** | C5 8/8 cells hit; mask × command truth table matches the reference. |
| **Status** | planned |

### X005 — log_fill_drain_mix

| Field | Detail |
|-------|--------|
| **Category** | Log FIFO occupancy × LOG_POP burst sweep |
| **Axes covered** | C4 (primary, 15 cells), C1 (secondary) |
| **Goal** | Sweep the full 5×3 C4 matrix by deliberately steering the log FIFO through every occupancy bin (empty, low<25%, mid, high>75%, near-full) while popping with each of the 3 burst lengths {1, 4, 16}. |
| **Setup** | runctl_sink = `always-ready`. upload_sink = `always-ready`. Log FIFO depth = `LOG_DEPTH` per RTL parameter; "low/mid/high/near-full" thresholds are 25% / 50% / 75% / ≥87.5% of `LOG_DEPTH` sub-words. |
| **Stimulus** | 1. Empty phase: read LOG_STATUS, pop 1 sub-word (returns 0), record cell C4[empty×1]. 2. Push 1 command (= 4 sub-words), pop 1 (cell C4[low×1]), pop 4 (cell C4[empty×4]). 3. Push commands until `rdusedw` enters the mid band, pop 4 (mid×4), pop 16 (mid×16). 4. Push until high band, pop 1 (high×1), pop 16 (high×16). 5. Push until near-full, pop 4 (near-full×4), pop 16 (near-full×16), pop 1 (near-full×1). 6. Drain until low band, burst 16 (low×16) then 4 (low×4). 7. Drain to empty, verify rdempty. |
| **Expected** | 1. Every popped sub-word matches the scoreboard reference for that command. 2. `rdusedw` trajectory matches monitor samples. 3. No torn log entries even when pops race with writes. |
| **Cells hit** | C4 full 15-cell matrix; C1[{RS,ST,EN,DI} × continuous-ready] for filler commands. |
| **Pass** | C4 15/15 cells hit; scoreboard agrees on all sub-words. |
| **Status** | planned |

### X006 — upload_backpressure_mix

| Field | Detail |
|-------|--------|
| **Category** | Command class × upload backpressure sweep |
| **Axes covered** | C1 (primary, full 30-cell matrix) |
| **Goal** | Close the full C1 matrix: 10 synclink command classes × 3 upload backpressure modes. Both RUN_PREPARE and END_RUN produce upload ack packets; the other 8 classes are cross-sampled because they still traverse the host path while upload backpressure is applied and C1 is defined as `cmd × upload_bp`, not `cmd × has_ack`. |
| **Setup** | runctl_sink = `always-ready`. The three upload backpressure patterns are tagged per DV_PLAN C1 axis names: `continuous-ready`, `toggled` (= `1-clk-stutter`), `held-low` for 64 cycles. |
| **Stimulus** | For each backpressure mode in {continuous-ready, toggled, held-low}: 1. Reset upload sink to the mode. 2. Send one command of each class (RP, RS, ST, ER, AB, RST with mask=0x5A5A, SRST with mask=0x5A5A, EN, DI, AD). 3. For held-low, release upload ready after each command completes so the FSM drains before the next. |
| **Expected** | 1. Exactly two upload ack packets per mode (K30.7 after RP, K29.7 after ER), never more. 2. Under `held-low`, upload FSM stalls for exactly 64 cycles and then emits the ack. 3. Non-ack commands do not spuriously assert upload valid. |
| **Cells hit** | C1 full 30-cell matrix: {RP,RS,ST,ER,AB,RST,SRST,EN,DI,AD} × {continuous-ready, toggled, held-low}. |
| **Pass** | C1 30/30 cells hit; upload scoreboard clean. |
| **Status** | planned |

### X007 — runctl_latency_sweep

| Field | Detail |
|-------|--------|
| **Category** | runctl ready latency sweep |
| **Axes covered** | C2 (primary, full 4-cell matrix), C3 (incidental) |
| **Goal** | Sweep runctl ready latency ∈ {0, 1, mid=8, max=64} while the host FSM is in POSTING, and prove the recv FSM never deadlocks. |
| **Setup** | upload_sink = `always-ready`. Log FIFO empty. |
| **Stimulus** | For each latency L in {0, 1, 8, 64}: 1. Configure runctl_sink to `held-low` with release-on-request after L cycles from runctl_valid rising. 2. Send a RUN_SYNC followed by a START_RUN. 3. Observe recv_state stall at POSTING via STATUS.recv_state_enc (CSR read while stalled → also feeds C3). 4. Release ready, let both drain. |
| **Expected** | 1. Exactly 2 runctl transactions per iteration. 2. Stall duration ≈ L lvdspll cycles. 3. No watchdog / no FSM hang. |
| **Cells hit** | C2[L=0 × POSTING], C2[L=1 × POSTING], C2[L=mid × POSTING], C2[L=max × POSTING]; C3[read×POSTING]. |
| **Pass** | C2 4/4 cells hit. |
| **Status** | planned |

### X008 — dual_reset_lvds_first

| Field | Detail |
|-------|--------|
| **Category** | Dual-reset ordering |
| **Axes covered** | C6 (primary, lvds-first cell), C1 (incidental on post-reset traffic) |
| **Goal** | Cover C6[lvds-first]: verify both clock domains return to a clean idle when `lvdspll_reset` is asserted first and `mm_reset` follows. |
| **Setup** | Pre-load SCRATCH=0xA5A5_A5A5, CONTROL.rst_mask=11, send 2 commands into the log FIFO so that non-default state is observable. |
| **Stimulus** | 1. Assert `lvdspll_reset`. 2. After 8 lvdspll cycles, assert `mm_reset`. 3. Hold both for 16 cycles of the slower clock. 4. Release `lvdspll_reset` first, then `mm_reset`. 5. Send a RUN_SYNC command post-release. |
| **Expected** | 1. All CSRs read default after release. 2. SCRATCH=0, CONTROL=0, LOG_STATUS.rdempty=1, RX_CMD_COUNT=0 (post-reset reset of mm-side counters), dp/ct_hard_reset=0. 3. The post-release RUN_SYNC is accepted and incremented RX_CMD_COUNT to 1. |
| **Cells hit** | C6[lvds-first]; C1[RS × continuous-ready]. |
| **Pass** | C6[lvds-first] hit; scoreboard agrees DUT came up clean. |
| **Status** | planned |

### X009 — dual_reset_mm_first

| Field | Detail |
|-------|--------|
| **Category** | Dual-reset ordering |
| **Axes covered** | C6 (primary, mm-first cell), C1 (incidental) |
| **Goal** | Cover C6[mm-first]. Same intent as X008 with reversed ordering. |
| **Setup** | Same non-default pre-load as X008. |
| **Stimulus** | 1. Assert `mm_reset`. 2. After 8 mm_clk cycles, assert `lvdspll_reset`. 3. Hold both ≥16 slow-clock cycles. 4. Release `mm_reset` first, then `lvdspll_reset`. 5. Send an END_RUN post-release (exercises upload-ack path after reset). |
| **Expected** | Same as X008; additionally verify the upload path emits exactly one K29.7 ack after the post-release END_RUN. |
| **Cells hit** | C6[mm-first]; C1[ER × continuous-ready]. |
| **Pass** | C6[mm-first] hit; upload ack correct. |
| **Status** | planned |

### X010 — dual_reset_simul

| Field | Detail |
|-------|--------|
| **Category** | Dual-reset ordering |
| **Axes covered** | C6 (primary, simultaneous cell), C1 (incidental), C5 (incidental) |
| **Goal** | Cover C6[simultaneous]. Additionally exercise CMD_RESET right before and after the dual reset to catch any residual hard_reset output glitches through the reset event. |
| **Setup** | Pre-load as in X008; also set rst_mask=00 so CMD_RESET can drive the outputs. |
| **Stimulus** | 1. Send CMD_RESET (assert=0x00FF) — dp/ct_hard_reset go high. 2. Assert `lvdspll_reset` and `mm_reset` on the same simulation time step. 3. Hold ≥16 slow-clock cycles. 4. Release both simultaneously. 5. Send CMD_STOP_RESET (release=0x00FF). |
| **Expected** | 1. After release, dp/ct_hard_reset are 0 (reset dominates). 2. Post-reset CMD_STOP_RESET is a no-op on the outputs (already 0) but still updates RESET_MASK[31:16]. 3. No SVA firings on the reset or CDC monitors. |
| **Cells hit** | C6[simultaneous]; C1[RST × continuous-ready], C1[SRST × continuous-ready]; C5[00×RST], C5[00×SRST]. |
| **Pass** | C6[simultaneous] hit. |
| **Status** | planned |

### X011 — local_cmd_phase_mix

| Field | Detail |
|-------|--------|
| **Category** | local_cmd submit phase × command class sweep |
| **Axes covered** | C7 (primary, full 30-cell matrix), C3 (incidental) |
| **Goal** | Close the full C7 matrix. Submit every one of the 10 command classes via LOCAL_CMD in each of the 3 recv FSM phases {IDLE, RX_PAYLOAD, POSTING}. |
| **Setup** | runctl_sink = `8-clk-hold` (to make POSTING reachable). upload_sink = `always-ready`. |
| **Stimulus** | Outer loop over phase P in {IDLE, RX_PAYLOAD, POSTING}, inner loop over command C in the 10-class set: 1. For P=IDLE: ensure no synclink activity, LOCAL_CMD(C) write, wait for busy clear. 2. For P=RX_PAYLOAD: start a synclink CMD_RESET, stall after the opcode, LOCAL_CMD(C) write during the stall, resume payload. 3. For P=POSTING: fill runctl buffer to cause POSTING stall, LOCAL_CMD(C) write, release runctl_ready. |
| **Expected** | 1. Each LOCAL_CMD write is accepted (busy low at submit time). 2. Toggle handshake completes before the next submit. 3. Scoreboard observes each command's fanout (except AD which only updates FPGA_ADDRESS). |
| **Cells hit** | C7 full 30-cell matrix: {IDLE, RX_PAYLOAD, POSTING} × {RP, RS, ST, ER, AB, RST, SRST, EN, DI, AD}; C3[write × {IDLE, RX_PAYLOAD, POSTING}]. |
| **Pass** | C7 30/30 cells hit; local_cmd_busy never drops a submitted word. |
| **Status** | planned |

### X012 — long_random_run

| Field | Detail |
|-------|--------|
| **Category** | Long random regression |
| **Axes covered** | All 7 (C1–C7) as an opportunistic mop-up |
| **Goal** | 5000 mixed-command transactions with randomised CSR activity, backpressure patterns, and reset-mask combos, to catch cells missed by the directed sweeps and to stress long-run counter/CDC paths. |
| **Setup** | Fixed `+SEED=` per regression bucket. runctl_sink and upload_sink independently cycle through {always-ready, 1-clk-stutter, 8-clk-hold, random-LCG} on a per-100-command epoch. CSR agent alternates read / write / idle epochs. |
| **Stimulus** | 1. LCG-draw a command class per step (uniform over the 10 classes). 2. LCG-draw a payload value from {0, mid, all-ones} for payload-bearing commands. 3. 20% of steps substitute a LOCAL_CMD submit for a synclink send. 4. Every 500 steps, toggle CONTROL.rst_mask and send a RST/SRST pair. 5. Every 1000 steps, burst-pop the log FIFO by {1, 4, 16}. |
| **Expected** | 1. RX_CMD_COUNT, RX_ERR_COUNT, LOG_STATUS all agree with the scoreboard. 2. No SVA firings. 3. At exit, `report_coverage()` shows zero `UNCOVERED:` lines on C1–C7. |
| **Cells hit** | Opportunistic across all 102 cells; quantitative closure is the directed tests' responsibility. X012 is the safety net. |
| **Pass** | Post-regression cross coverage = 100%; scoreboard clean. |
| **Status** | planned |

### X013 — log_pop_burst_during_cmd

| Field | Detail |
|-------|--------|
| **Category** | LOG_POP burst concurrent with synclink traffic |
| **Axes covered** | C4 (primary), C3 (secondary), C1 (incidental) |
| **Goal** | Verify LOG_POP bursts of 16 sub-words are atomic with respect to concurrent writes to the log FIFO from the RUN_PREPARE/END_RUN execution path. |
| **Setup** | runctl_sink = `always-ready`. upload_sink = `1-clk-stutter` (so upload ack handling interleaves with log writes). Pre-fill the log FIFO to mid occupancy. |
| **Stimulus** | 1. Start a back-to-back synclink stream of 8 × RUN_PREPARE (each = 5 bytes + 4 log sub-words). 2. Concurrently the CSR agent reads LOG_POP 16 times as a tight burst, then pauses, then reads another 16. 3. Repeat with 8 × END_RUN. |
| **Expected** | 1. No sub-word is lost or duplicated. 2. Popped sub-words correspond to commands in issue order. 3. Upload ack count = 8 per phase. |
| **Cells hit** | C4[mid × 16], C4[high × 16], C4[mid × 4]; C3[read × LOG_WR] (LOG_POP read landing on a log-write cycle); C1[RP × 1-clk-stutter], C1[ER × 1-clk-stutter]. |
| **Pass** | ≥3 additional C4 cells hit beyond X005's baseline; no torn entries. |
| **Status** | planned |

### X014 — meta_sweep_during_cmd

| Field | Detail |
|-------|--------|
| **Category** | META page selector sweep × recv state |
| **Axes covered** | C3 (primary, write×* and read×*), C1 (incidental) |
| **Goal** | Verify META page selector writes/reads are non-disruptive and all four META pages are observable while the recv FSM is active. Reinforces C3 coverage for tests where X001 / X002 missed specific cells due to timing jitter. |
| **Setup** | runctl_sink = `random-LCG`. upload_sink = `always-ready`. |
| **Stimulus** | 1. CSR agent cycles META selector writes 0→1→2→3→0→... with a paired read after each write. 2. Simultaneously stream 40 mixed synclink commands. |
| **Expected** | 1. Each META read returns the page matching the most recent selector write. 2. Command stream delivers without interference. |
| **Cells hit** | C3[write×IDLE], C3[write×RX_PAYLOAD], C3[read×IDLE], C3[read×RX_PAYLOAD]; C1[{RS,ST,ER,AB} × continuous-ready]. |
| **Pass** | META page coverage bin full; C3 read/write rows reinforced. |
| **Status** | planned |

### X015 — scratch_pattern_during_cmd

| Field | Detail |
|-------|--------|
| **Category** | SCRATCH pattern sweep × command traffic |
| **Axes covered** | C3 (primary, write × POSTING/LOG_WR), C1 (incidental) |
| **Goal** | Cover the SCRATCH pattern bin group (0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555) while commands are flowing and runctl is stalled, reinforcing the C3 `write × POSTING` and `write × LOG_WR` cells. |
| **Setup** | runctl_sink = `8-clk-hold`. upload_sink = `always-ready`. |
| **Stimulus** | 1. Start a 12-command synclink stream (RS/ST/EN/DI/RP). 2. During each POSTING stall, CSR agent writes one of the four SCRATCH patterns in sequence. 3. After the stream, CSR agent reads SCRATCH to confirm the last pattern. |
| **Expected** | 1. SCRATCH readback = last-written pattern. 2. All 12 commands delivered. 3. scratch_pattern bin group 4/4 bins hit by end of test. |
| **Cells hit** | C3[write × POSTING], C3[write × LOG_WR]; C1[{RS,ST,EN,DI,RP} × continuous-ready]. |
| **Pass** | C3 `write × {POSTING, LOG_WR}` hit; scratch_pattern bin group 4/4 hit. |
| **Status** | planned |

---

## 3. Cross-axis minimum check

| Test  | Axes touched (≥2 required) | Count |
|-------|----------------------------|-------|
| X001  | C3, C1, C7                 | 3 |
| X002  | C3, C1                     | 2 |
| X003  | C7, C1, C3                 | 3 |
| X004  | C5, C3                     | 2 |
| X005  | C4, C1                     | 2 |
| X006  | C1 (30 cells) + C3 idle backdrop | 1 primary + 1 incidental |
| X007  | C2, C3                     | 2 |
| X008  | C6, C1                     | 2 |
| X009  | C6, C1                     | 2 |
| X010  | C6, C1, C5                 | 3 |
| X011  | C7, C3                     | 2 |
| X012  | C1–C7 (all)                | 7 |
| X013  | C4, C3, C1                 | 3 |
| X014  | C3, C1                     | 2 |
| X015  | C3, C1                     | 2 |

Every X-test covers ≥2 cross axes. X006 is flagged: its primary contribution
is the C1 matrix, and its only secondary axis hit is the `C3[idle × *]` row
that any steady-state test contributes implicitly. This is considered
sufficient because C1 is the largest axis and needs a dedicated sweep; a
deeper secondary axis would dilute the sweep discipline. Recorded as a drift
note in section 5.

---

## 4. Traceability: test → cross cells

The table below is the audit trail for signoff. A cell is considered
"covered" if at least one test in the row set lists it under **Cells hit**
and the corresponding counter in `cov_cross` is non-zero in the regression
report.

### 4.1 C1 — synclink cmd class × upload backpressure (30 cells)

| Command \ Upload BP | continuous-ready | toggled (1-clk-stutter) | held-low |
|---|---|---|---|
| RP (0x10) | X001, X006, X008/X009, X010, X011, X014, X015 | X006, X013 | X006 |
| RS (0x11) | X001, X002, X003, X006, X007, X008, X011, X014 | X006 | X006 |
| ST (0x12) | X001, X002, X006, X007, X011, X014, X015 | X006 | X006 |
| ER (0x13) | X001, X002, X006, X009, X011, X014 | X006, X013 | X006 |
| AB (0x14) | X001, X002, X003, X006, X011, X014 | X006 | X006 |
| RST (0x30) | X001, X003, X004, X006, X010, X011 | X006 | X006 |
| SRST (0x31) | X001, X004, X006, X010, X011 | X006 | X006 |
| EN (0x32) | X001, X002, X006, X011, X014, X015 | X006 | X006 |
| DI (0x33) | X001, X002, X006, X011, X014, X015 | X006 | X006 |
| AD (0x40) | X001, X002, X006, X011 | X006 | X006 |

### 4.2 C2 — runctl ready latency × POSTING stall (4 cells)

| Latency | POSTING |
|---|---|
| 0     | X007 |
| 1     | X007 |
| mid=8 | X007, X003, X011, X015 |
| max=64| X007 |

### 4.3 C3 — CSR activity × recv_state (12 cells)

| CSR \ recv_state | IDLE | RX_PAYLOAD | POSTING | LOG_WR |
|---|---|---|---|---|
| read  | X001, X012, X014 | X001, X012, X014 | X001, X007, X012 | X001, X013, X012 |
| write | X002, X004, X011, X012, X014 | X002, X003, X011, X012, X014 | X002, X003, X011, X012, X015 | X002, X012, X015 |
| idle  | X006 (sink-only epochs), X012 | X006, X012 | X006, X012 | X006, X012 |

### 4.4 C4 — log FIFO occupancy × LOG_POP burst (15 cells)

| Occupancy \ Burst | 1 | 4 | 16 |
|---|---|---|---|
| empty     | X005 | X005 | X005, X013 |
| low<25%   | X005 | X005 | X005 |
| mid       | X005, X013 | X005, X013 | X005, X013 |
| high>75%  | X005 | X005 | X005, X013 |
| near-full | X005 | X005 | X005 |

### 4.5 C5 — rst_mask combo × reset cmd (8 cells)

| rst_mask {dp,ct} \ cmd | CMD_RESET | CMD_STOP_RESET |
|---|---|---|
| 00 | X004, X010 | X004, X010 |
| 01 | X004 | X004 |
| 10 | X004 | X004 |
| 11 | X004 | X004 |

### 4.6 C6 — lvdspll_reset × mm_reset ordering (3 cells)

| Ordering | Test |
|---|---|
| lvds-first   | X008 |
| mm-first     | X009 |
| simultaneous | X010 |

### 4.7 C7 — local_cmd submit phase × command class (30 cells)

| Phase \ Command | RP | RS | ST | ER | AB | RST | SRST | EN | DI | AD |
|---|---|---|---|---|---|---|---|---|---|---|
| IDLE        | X011 | X011, X001 | X011 | X011 | X011 | X011 | X011 | X011 | X011 | X011 |
| RX_PAYLOAD  | X011 | X011, X003 | X011 | X011 | X011, X003 | X011 | X011 | X011 | X011 | X011 |
| POSTING     | X011 | X011, X003 | X011 | X011 | X011, X003 | X011 | X011 | X011 | X011 | X011 |

X012 (long random run) is an implicit contributor to every C1–C7 cell and is
the safety-net test. It is not listed in every cell above to keep the tables
readable, but the regression coverage report must show it as a backup hitter.

### 4.8 Cell-count check

| Axis | Defined | Covered by directed X-tests | Covered including X012 |
|------|---------|------------------------------|------------------------|
| C1   | 30      | 30                           | 30 |
| C2   | 4       | 4                            | 4  |
| C3   | 12      | 12                           | 12 |
| C4   | 15      | 15                           | 15 |
| C5   | 8       | 8                            | 8  |
| C6   | 3       | 3                            | 3  |
| C7   | 30      | 30                           | 30 |
| **Total** | **102** | **102**                   | **102** |

---

## 5. Plan drift notes

- **Pattern naming.** DV_PLAN §5.3 axis C1 uses the backpressure labels
  `continuous-ready`, `toggled`, `held-low`. This file aliases
  `toggled ≡ 1-clk-stutter` and treats `continuous-ready ≡ always-ready`.
  When `DV_HARNESS.md` lands, the agent class names MUST match the left-hand
  side (the DV_PLAN labels). Proposed additional names `8-clk-hold` and
  `random-LCG` are harness-internal and do not appear on the C1 axis.
- **C1 secondary-axis weakness (X006).** X006 is the only X-test whose
  secondary axis hit is limited to the implicit `C3[idle × *]` row. This is
  accepted because X006 is structured as an exhaustive C1 sweep and adding a
  second orthogonal axis would either linearly scale its cost or dilute the
  per-cell reproducibility. Flagged here for review during signoff.
- **C3 `idle × *` row.** The `CSR activity = idle` row of C3 is hit only by
  tests that have explicit idle CSR epochs (X006, X012). No dedicated test
  targets `idle × RX_PAYLOAD` or `idle × POSTING`; X012's random CSR epoch
  generator is responsible. If regression shows `UNCOVERED: cov_cross.C3[...]`
  on the idle row, add a small directed test (propose X016) rather than
  extending X012.
- **C4 near-full × 16 burst.** This cell is sensitive to the exact log FIFO
  depth parameter. X005 drives occupancy from writes, but if the depth is
  such that "near-full" is < 16 sub-words away from `rdfull`, a burst=16 pop
  cannot be issued without first pushing more commands mid-burst. The test
  handles this by pre-loading the FIFO before the near-full phase; if RTL
  changes the depth parameter, re-validate the thresholds.
- **Log FIFO exact occupancy thresholds.** The 5 bins `empty`, `low<25%`,
  `mid`, `high>75%`, `near-full` are parameterised off `LOG_DEPTH`. This file
  does not pin numeric thresholds because the RTL parameter is still in
  flight; the harness collector must expose the threshold constants so the
  scoreboard and this document stay in sync.
- **X016+ expansion.** DV_PLAN.md originally stopped at X015. The expansion
  tests X016..X100 below introduce new cross axes C8..C16 targeting design
  decisions and corner combinations that C1..C7 do not cover. They MUST be
  back-propagated into DV_PLAN §6.3 as a sign-off prerequisite; until that
  happens, this file is the authoritative registry.

---

## 6. Expanded cross axes (C8..C16)

These nine additional axes cover frozen design decisions (LOCAL_CMD
waitrequest stall, log-FIFO drop-new, soft_reset CDC drain, GTS_L shadow
latch, CSR during mm_reset, etc.) that C1..C7 leave implicit. Only the
representative cells listed below are required for sign-off; the full
matrices are documented for future expansion.

| Axis | Definition | Full cells | Representative tests |
|------|------------|-----------:|---------------------:|
| C8   | CSR read target (10 hot words) × concurrent command class (10) | 100 | 12 (diagonal + corners) |
| C9   | CSR writable target (4) × recv_state (4) | 16 | 10 |
| C10  | Log FIFO occupancy bin (5) × CSR activity class (3) | 15 | 8 |
| C11  | Upload backpressure (3) × runctl backpressure (3) × {RP,ER} (2) | 18 | 8 |
| C12  | rst_mask combo (4) × reset cmd (2) × pipe_r2h_done latency (2) | 16 | 8 |
| C13  | GTS wrap phase (3) × CSR read type (GTS_L, GTS_H, STATUS) (3) | 9 | 6 |
| C14  | Soft_reset phase (5 recv states) × snap-update in flight (2) | 10 | 6 |
| C15  | LOCAL_CMD burst length (3) × command mix (3: all-same, RR, random) | 9 | 6 |
| C16  | Clock ratio (3: mm<lvds, mm=lvds, mm>lvds) × scenario (3: long random, counter saturation, log fill/drain) | 9 | 6 |

Sign-off rule for the expanded axes: every representative cell must be hit
at least once in regression, counted via the same `cov_cross` collector
convention as C1..C7. Where a cell is judged infeasible with directed
stimulus (see section 8 below), the `long_random` tests X100..X104 are the
fall-back hitter.

---

## 7. Expansion X-test cards (X016..X109)

Compact format. Each row is self-contained; stimulus and expected behaviour
must match the frozen design decisions listed in DV_CROSS.md section 0 and
DV_PLAN §6.3. Backpressure pattern names are the same as sections 0 / 2.

### 7.1 C8 — CSR read target × concurrent command class (12 representative)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X016_csr_read_status_during_all10_cmds | runctl_sink=`random-LCG`, upload_sink=`always-ready`. CSR agent reads STATUS back-to-back with 0..2-cycle gaps while a synclink burst of 20 commands cycles through all 10 classes. | Every STATUS read atomic (1 mm_clk), recv_state_enc field moves through the four encodings across samples, no command dropped. | planned |
| X017_csr_read_last_cmd_during_rp_stream | upload_sink=`held-low` for 32 cycles then released. CSR agent reads LAST_CMD while a stream of 8 × RUN_PREPARE runs. | LAST_CMD shadow monotonically advances, equals the most recently completed RP opcode at each sampled read. | planned |
| X018_csr_read_run_number_during_start_run | Issue RUN_PREPARE(run=N), then START_RUN. CSR agent reads RUN_NUMBER on each lvdspll epoch across the pair. | RUN_NUMBER latches to N on RP post-commit and is stable across the subsequent ST. | planned |
| X019_csr_read_reset_mask_during_rst_srst | Back-to-back CMD_RESET(assert=0xAA55) / CMD_STOP_RESET(release=0xAA55). CSR agent reads RESET_MASK every 4 cycles. | RESET_MASK[15:0] reflects assert mask after RST, [31:16] reflects release mask after SRST, intermediate reads atomic. | planned |
| X020_csr_read_fpga_address_during_address_cmd | Send ADDRESS(0x40) with payload 0xCAFE followed by 5 mixed commands. CSR reads FPGA_ADDRESS throughout. | FPGA_ADDRESS updates exactly once on ADDRESS commit; other commands leave it unchanged; CMD_ADDRESS does not fan out on runctl (no runctl transaction for AD). | planned |
| X021_csr_read_recv_ts_l_during_rx_payload | runctl_sink=`held-low`. Stall a CMD_RESET synclink payload mid-word. CSR agent reads RECV_TS_L every cycle during the stall. | RECV_TS_L stable (latched at opcode receive), consistent with RECV_TS_H shadow. | planned |
| X022_csr_read_exec_ts_l_during_posting | Stall runctl_ready for 64 cycles during a RUN_SYNC POSTING phase. CSR reads EXEC_TS_L during stall and after release. | EXEC_TS_L latched on command exec; read during stall returns previous commit's stamp, updates only after current RUN_SYNC posts. | planned |
| X023_csr_read_gts_l_during_end_run | Issue END_RUN while CSR agent reads GTS_L → GTS_H back-to-back. Upload_sink=`always-ready`. | GTS_L read latches GTS_H shadow atomically; subsequent GTS_H read returns the matching upper word even if counter advanced during the END_RUN. | planned |
| X024_csr_read_rx_cmd_count_during_burst | Send a 40-command burst (all classes). CSR agent polls RX_CMD_COUNT between each command. | Counter increments by 1 per accepted command, saturates at 0xFFFFFFFF if forced (tested via X051). | planned |
| X025_csr_read_log_pop_during_run_prepare_burst | Send 16 × RUN_PREPARE while CSR agent issues LOG_POP reads at rate 1/2 cycles. | LOG_POP returns log sub-words in FIFO order with no torn entries; after drain, LOG_POP returns 0 and LOG_STATUS.rdempty=1. | planned |
| X026_csr_read_corners_diagonal_sweep | For each of {STATUS, LAST_CMD, RUN_NUMBER, RESET_MASK, FPGA_ADDRESS, RECV_TS_L, EXEC_TS_L, GTS_L, RX_CMD_COUNT, LOG_POP} paired diagonally with command {RP, RS, ST, ER, AB, RST, SRST, EN, DI, AD}, issue one single-command transaction. | Every (read-target, command) diagonal cell hit ≥1 in cov_cross.C8. | planned |
| X027_csr_read_corners_off_diagonal | Corner combinations missed by X026 diagonal: {LOG_POP × RST}, {GTS_L × AD}, {RESET_MASK × ER}, {RX_CMD_COUNT × AB}. | Scoreboard agrees; the off-diagonal cells are hit at least once each. | planned |

### 7.2 C9 — CSR writable target × recv_state (10 representative)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X028_meta_write_during_idle | runctl_sink=`always-ready`, no synclink activity. Write META page selector 0→1→2→3 with paired reads. | Each META read returns matching page; no spurious recv_state transitions. | planned |
| X029_meta_write_during_rx_payload | Stall a synclink CMD_RESET payload mid-stream. Write META selector during RX_PAYLOAD. | META updates without interfering; synclink resumes and commits cleanly. | planned |
| X030_meta_write_during_posting | runctl_sink=`held-low` for 32 cycles. Write META selector during POSTING stall. | META updates; post-stall runctl transaction completes. | planned |
| X031_control_soft_reset_during_idle | Write CONTROL.soft_reset=1 while recv is idle, log FIFO populated with 4 entries. | CDC toggle pulse to lvds side; log FIFO drains on mm side; GTS counter NOT reset; scratch unchanged. | planned |
| X032_control_soft_reset_during_log_wr | Send a RUN_PREPARE, and assert CONTROL.soft_reset in the same CSR write epoch as the LOG_WR cycle. | Soft-reset drains the log FIFO including the entry in flight; no torn writes; GTS preserved. | planned |
| X033_scratch_write_pattern_during_rx_payload | Stall a CMD_RESET payload; write SCRATCH with {0,0xFFFFFFFF,0xAAAAAAAA,0x55555555} rotation. | SCRATCH readback = last pattern; recv FSM unaffected. | planned |
| X034_scratch_write_during_posting | Write SCRATCH during a 32-cycle POSTING stall. | SCRATCH updates; no deadlock. | planned |
| X035_local_cmd_write_during_idle | LOCAL_CMD submit RS with recv idle. | FSM enters RX_PAYLOAD from local path; priority 1 (local) beats priority 2 (synclink). | planned |
| X036_local_cmd_write_busy_waitrequest | LOCAL_CMD submit RS; before busy clears, submit a second LOCAL_CMD write. | Second write sees waitrequest=1 until handshake completes, then commits. No lost commands. | planned |
| X037_control_log_flush_during_log_wr | Assert CONTROL.log_flush while a RUN_PREPARE is writing log sub-words. | mm-side drain only; lvds side unaffected; log empties after the in-flight sub-words commit. | planned |

### 7.3 C10 — log FIFO occupancy × CSR activity class (8 representative)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X038_log_empty_csr_read_burst | Log empty. CSR read-only burst of 32 reads across all hot words. | All reads atomic; LOG_STATUS.rdempty stable 1. | planned |
| X039_log_low_csr_write_burst | Fill log to low<25%. CSR write-only burst (SCRATCH/CONTROL bit toggles). | Writes non-intrusive; log occupancy stable. | planned |
| X040_log_mid_csr_mixed | Fill log to mid. CSR agent alternates read/write epochs. | Mixed traffic has no effect on log content; LOG_POP readback consistent. | planned |
| X041_log_high_csr_idle | Fill log to high>75%. CSR idle epoch of 1024 cycles. | No spurious activity; log occupancy stable at the high bin. | planned |
| X042_log_near_full_drop_new | Fill log to 1 sub-word below full, then send a RUN_PREPARE (4 sub-words). | Drop-new policy: 3 sub-words dropped, drop counter saturates accordingly; accepted sub-word is the first of the four. | planned |
| X043_log_full_drop_counter_saturate | Force drop counter to 0xFFFFFFFF by sustained writes at full occupancy (gated via LCG push pattern). | Drop counter saturates at 0xFFFFFFFF, does not wrap. | planned |
| X044_log_high_csr_read_pop | Log high. CSR read burst including LOG_POP×16. | LOG_POP drains 16 sub-words; subsequent occupancy in mid bin. | planned |
| X045_log_empty_log_pop_returns_zero | Log empty. CSR LOG_POP read. | Returns 0; LOG_STATUS.rdempty=1 remains asserted. | planned |

### 7.4 C11 — upload BP × runctl BP × {RP, ER} (8 representative)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X046_bp_contready_contready_rp | runctl=`always-ready`, upload=`always-ready`. Send RP. | 1 runctl txn, 1 upload K30.7 ack, minimum latency. | planned |
| X047_bp_toggled_toggled_rp | runctl=`1-clk-stutter`, upload=`1-clk-stutter`. Send RP. | 1 ack; stall durations ≈ 2× baseline; no deadlock. | planned |
| X048_bp_heldlow_contready_rp | runctl=`held-low` 64 cycles, upload=`always-ready`. Send RP. | Ack emitted after runctl release; recv stalls in POSTING for ~64 cycles. | planned |
| X049_bp_contready_heldlow_rp | runctl=`always-ready`, upload=`held-low` 64 cycles. Send RP. | Ack emitted after upload release; runctl txn completes immediately. | planned |
| X050_bp_heldlow_heldlow_rp | Both paths held-low 64 cycles, staggered release (runctl first). | Single ack emitted only after both paths clear; order-independent commit. | planned |
| X051_bp_toggled_heldlow_er | runctl=`1-clk-stutter`, upload=`held-low` 32 cycles. Send END_RUN. | Exactly one K29.7 ack after upload release; no spurious acks during held-low window. | planned |
| X052_bp_heldlow_toggled_er | runctl=`held-low` 32 cycles, upload=`1-clk-stutter`. Send END_RUN. | 1 runctl txn once released; ack emitted with the stutter pattern preserved. | planned |
| X053_bp_random_lcg_both_mix | Both paths `random-LCG` seeded 0x5A5A. 8 RP + 8 ER mix. | 16 acks total (8 K30.7 + 8 K29.7), order matches issue order, no loss. | planned |

### 7.5 C12 — rst_mask × reset cmd × pipe_r2h_done latency (8 representative)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X054_mask00_rst_fast_r2h | rst_mask=00, CMD_RESET(assert=0x00FF), `pipe_r2h_done` rise fast (next mm_clk). | dp/ct_hard_reset rise on r2h_done edge; RESET_MASK[15:0]=0x00FF. | planned |
| X055_mask00_rst_slow_r2h | rst_mask=00, CMD_RESET(assert=0x00FF), r2h_done delayed 16 lvdspll cycles. | Same final state as X054; asserted timing shifted by 16 cycles, no glitches in between. | planned |
| X056_mask11_rst_fast_r2h | rst_mask=11, CMD_RESET, fast r2h_done. | dp/ct_hard_reset stay low; RESET_MASK still records the assert. | planned |
| X057_mask11_rst_slow_r2h | rst_mask=11, CMD_RESET, slow r2h_done. | Same as X056; no output glitch during the slow handshake. | planned |
| X058_mask01_srst_fast_r2h | rst_mask=01, CMD_STOP_RESET, fast r2h_done. | ct_hard_reset deasserts (was preset); dp untouched. | planned |
| X059_mask10_srst_slow_r2h | rst_mask=10, CMD_STOP_RESET, slow r2h_done. | dp_hard_reset deasserts; ct untouched. | planned |
| X060_mask00_rst_srst_back_to_back_fast | rst_mask=00, CMD_RESET then CMD_STOP_RESET both with fast r2h_done. | Outputs toggle high then low, each on its own r2h_done rise; no overlap hazard. | planned |
| X061_mask00_rst_srst_back_to_back_slow | Same as X060 with slow r2h_done on both. | Same final state; exercises the longer CDC path. | planned |

### 7.6 C13 — GTS wrap phase × CSR read type (6 representative)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X062_gts_before_wrap_read_gtsl | Set GTS close to 0xFFFF_FFFE (mid-word); CSR reads GTS_L then GTS_H. | GTS_L latches the low word; GTS_H read returns the matching upper word pre-wrap. | planned |
| X063_gts_at_wrap_read_gtsl | Advance GTS exactly through the GTS_L wrap (0xFFFFFFFF → 0x00000000). CSR read GTS_L at the wrap edge. | GTS_L read atomic with respect to wrap; GTS_H increments by 1 only after read completes. | planned |
| X064_gts_after_wrap_read_gtsl | After wrap, read GTS_L then GTS_H. | GTS_L returns the post-wrap low word; GTS_H shadow reflects the incremented upper word. | planned |
| X065_gts_at_wrap_read_gtsh | Read GTS_H (without first reading GTS_L) at the wrap edge. | GTS_H returns the current upper word; no shadow latched; subsequent GTS_L read latches the live value. | planned |
| X066_gts_mid_run_read_status | Read STATUS repeatedly while GTS is running. | STATUS returns atomic snapshots; GTS_run flag stable. | planned |
| X067_gts_wrap_during_end_run | Force GTS wrap during an END_RUN execution. | END_RUN commits; upload K29.7 ack contains the post-exec timestamp; GTS_L/GTS_H shadow consistent after the ack. | planned |

### 7.7 C14 — soft_reset phase × snap-update in-flight (6 representative)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X068_softrst_idle_no_snap | CONTROL.soft_reset=1 while recv idle, no snap update in flight. | CDC toggle pulse asserted; log drained; GTS untouched; CSR shadow consistent post-pulse. | planned |
| X069_softrst_rx_payload_no_snap | soft_reset during a stalled synclink payload. | lvds side drops the partial payload on the toggle edge; mm side drains log; recv returns to IDLE. | planned |
| X070_softrst_posting_snap_inflight | soft_reset during a POSTING stall while an RX_CMD_COUNT snap update is in flight across CDC. | Snap update completes or is cleanly dropped; no partial CSR shadow update; counters either old or new value, never torn. | planned |
| X071_softrst_log_wr_no_snap | soft_reset mid-LOG_WR. | Log FIFO drain wins; the in-flight log sub-word either commits fully or is dropped, never torn. | planned |
| X072_softrst_log_wr_snap_inflight | soft_reset mid-LOG_WR while RX_CMD_COUNT snap update is crossing CDC. | Same as X071 for log; snap update resolved atomically; scoreboard agrees on both counter and log state. | planned |
| X073_softrst_idle_back_to_back | Two CONTROL.soft_reset pulses within 8 mm_clk cycles. | Second pulse waits for the first handshake to complete (waitrequest enforcement), then takes effect; no lost pulses. | planned |

### 7.8 C15 — LOCAL_CMD burst length × mix (6 representative)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X074_localcmd_burst1_allsame | Single LOCAL_CMD of EN. | Busy clears within handshake latency; fanout matches spec. | planned |
| X075_localcmd_burst4_allsame | 4 × EN LOCAL_CMD back-to-back with waitrequest stall between each. | All 4 commit in order; RX_CMD_COUNT+=4. | planned |
| X076_localcmd_burst16_allsame | 16 × EN LOCAL_CMD back-to-back. | 16 commits; no CSR deadlock; waitrequest stalls are bounded. | planned |
| X077_localcmd_burst4_roundrobin | 4 LOCAL_CMD round-robin {RP, RS, ST, ER}. | Commits in order; upload emits K30.7 after RP and K29.7 after ER; runctl txn per command. | planned |
| X078_localcmd_burst16_roundrobin | 16 LOCAL_CMD round-robin through all 10 classes then wrap. | All commits; 16 in order; upload acks counted correctly. | planned |
| X079_localcmd_burst16_lcg_random | 16 LOCAL_CMD with classes drawn from LCG PRNG (seed 0xBEEFCAFE). | Scoreboard agrees on execution order and fanout; busy never drops a submitted word. | planned |

### 7.9 C16 — clock ratio × scenario (6 representative)

Note: the clock ratio axis is a harness setting, not an RTL parameter.
These tests are only runnable when the harness exposes programmable
mm_clk and lvdspll_clk periods. They MUST be gated by `+CLK_RATIO=` plusarg.

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X080_clkratio_mm_slower_long_random | mm_clk period = 2× lvdspll period. 10k-step long random run. | No deadlock; scoreboard clean; CDC SVA silent. | planned |
| X081_clkratio_mm_equal_counter_saturation | mm_clk = lvdspll period. Force RX_CMD_COUNT to saturate. | Counter saturates at 0xFFFFFFFF; no wrap; CSR read returns 0xFFFFFFFF stably. | planned |
| X082_clkratio_mm_faster_log_fill_drain | mm_clk period = 0.5× lvdspll period. Sweep log fill/drain through all 5 occupancy bins. | log FIFO behaves per drop-new policy; occupancy bins transition correctly despite fast mm-side pops. | planned |
| X083_clkratio_mm_slower_counter_saturation | mm_clk slower, drive RX_CMD_COUNT to saturation via synclink burst. | Saturates; lvds-to-mm CDC snap updates remain consistent. | planned |
| X084_clkratio_mm_equal_long_random | mm_clk = lvdspll. 50k-step long random run. | Scoreboard clean; all cov_cross axes touched at least opportunistically. | planned |
| X085_clkratio_mm_faster_long_random | mm_clk faster. 10k-step long random run. | Scoreboard clean; CDC SVA silent under mm-fast ratio. | planned |

### 7.10 Long random regressions (5 seeds)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X086_long_random_10k_seed1 | 10k-step mixed-stimulus regression, LCG seed=1. Epochs of 100 cycle through all backpressure patterns on runctl and upload; CSR epochs alternate read/write/idle; 20% LOCAL_CMD substitution; 2% soft_reset; 1% log_flush. | Scoreboard clean, cov_cross C1..C16 all hit opportunistically, no SVA firings. | planned |
| X087_long_random_50k_seed42 | 50k steps, LCG seed=42, same epoch schedule as X086. | Same pass criteria as X086; closes residual uncovered cells from directed tests. | planned |
| X088_long_random_100k_seed_deadbeef | 100k steps, LCG seed=0xDEADBEEF. | Same pass criteria; used as the overnight regression reference. | planned |
| X089_long_random_50k_seed_beefcafe | 50k steps, LCG seed=0xBEEFCAFE. | Same pass criteria; independent seed for variance. | planned |
| X090_long_random_50k_seed_5a5a5a5a | 50k steps, LCG seed=0x5A5A5A5A. | Same pass criteria; final seed. | planned |

### 7.11 Killer corner combinations (10 directed)

| ID | Stimulus | Expected | Status |
|----|----------|----------|--------|
| X091_lognearfull_softrst_synclink_inflight | Fill log to near-full. Start an 8-command synclink burst. On the 4th command mid-payload, assert CONTROL.soft_reset. | Soft-reset drains the log FIFO; in-flight synclink command is cleanly dropped at the CDC boundary; post-pulse the remaining 4 commands issue cleanly; no torn log entries. | planned |
| X092_csr_scratch_burst_localcmd_burst_synclink_burst | Three parallel agents: CSR writes SCRATCH rotating 4-pattern at rate 1/cycle; LOCAL_CMD burst of 8 commands; synclink burst of 8 commands. | All commands commit in a consistent scoreboarded order; SCRATCH readback = last pattern; no deadlock between the three paths. | planned |
| X093_mask_flip_rst_srst_log_drain_simul | Simultaneously: toggle CONTROL.rst_mask_dp; CMD_RESET; CONTROL.log_flush. | Mask takes effect before the RESET fanout decision; log drains; dp/ct_hard_reset output matches the new mask combo. | planned |
| X094_mm_reset_during_gtsl_read_snapshot | Begin a CSR read of GTS_L; before the response completes, assert mm_reset. | Read returns waitrequest until mm_reset deasserts; post-release the first GTS_L read returns 0 (GTS reset is not in scope of soft_reset but IS in scope of mm_reset? No — check: per frozen decision `CONTROL.soft_reset` does NOT reset GTS, but mm_reset is a hard domain reset). GTS_L shadow is invalidated on mm_reset; first post-reset read returns the freshly latched low word. | planned |
| X095_unknown_cmd_silent_drop_during_csr_read | Send an unknown opcode (e.g. 0xAA) via synclink while CSR reads STATUS. | Command silently dropped (no fanout, no log, no counter increment); RX_CMD_COUNT unchanged; STATUS read atomic. | planned |
| X096_reserved_csr_write_during_posting | Write a reserved CSR address during a POSTING stall. | 1-cycle accept with no effect; CSR shadow unchanged; FSM continues. | planned |
| X097_mm_reset_during_csr_burst | Assert mm_reset mid-CSR read burst. | CSR agent sees waitrequest=1 until mm_reset deasserts; no activity on CSR during the held reset. | planned |
| X098_local_cmd_priority_over_synclink_race | Submit LOCAL_CMD and synclink opcode on the same mm_clk edge with recv in IDLE. | LOCAL_CMD wins (priority 1); synclink waits until local handshake completes; no loss. | planned |
| X099_cmd_address_fanout_suppression | Send ADDRESS(0x40) + immediately START_RUN. | ADDRESS updates FPGA_ADDRESS CSR only; does NOT generate a runctl transaction; START_RUN immediately follows and produces its own runctl txn. | planned |
| X100_counter_saturation_all | Force RX_CMD_COUNT and RX_ERR_COUNT to 0xFFFFFFFF via sustained bursts (LCG-steered); verify both saturate and CONTROL.log_flush does not clear them. | Both counters read 0xFFFFFFFF; only explicit CSR clear-on-write (if implemented) or mm_reset resets them. | planned |

---

## 8. Expansion cross-axis minimum check

| Test range | Primary axes | Count |
|------------|--------------|-------|
| X016..X027 | C8                | 12 |
| X028..X037 | C9                | 10 |
| X038..X045 | C10               | 8  |
| X046..X053 | C11               | 8  |
| X054..X061 | C12               | 8  |
| X062..X067 | C13               | 6  |
| X068..X073 | C14               | 6  |
| X074..X079 | C15               | 6  |
| X080..X085 | C16               | 6  |
| X086..X090 | all (long random) | 5  |
| X091..X100 | corner kills      | 10 |

Each expansion test touches ≥2 cross axes: its named primary axis plus at
least C1 or C3 through concurrent synclink/CSR traffic. Long-random tests
touch all 16 axes opportunistically.

### 8.1 Axis combinations judged infeasible with directed stimulus

- **C8 full 10×10 matrix (100 cells).** Sampled only on a 10-cell diagonal
  plus 2 off-diagonal corners. Full closure is delegated to X086..X090
  long random regressions.
- **C14 snap-update-in-flight cell for every recv_state.** "In flight"
  requires a race between a specific mm-clk CDC edge and a soft_reset
  pulse; deterministic reproduction in RX_PAYLOAD and POSTING is
  currently brittle. X070 and X072 target the most stable phases; the
  others fall back to long random.
- **C16 clock-ratio axis.** Requires harness support for programmable
  clock periods. Until the harness exposes `+CLK_RATIO=`, X080..X085
  are blocked. Flag as `blocked:harness` in regression.
- **Log FIFO drop-new counter saturation (X043).** Requires 2^32 dropped
  sub-words; infeasible in real simulation time. Either preload the
  drop counter via a backdoor hook in the collector or tag this cell
  as `formal-only`.

---

**Total X-tests: 100** (X001..X015 original + X016..X100 expansion).
