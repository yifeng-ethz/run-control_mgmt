# DV Harness: runctl_mgmt_host UVM Environment

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**DUT:** `runctl_mgmt_host` (`rtl/runctl_mgmt_host.sv`)
**Author:** Yifeng Wang (yifenwan@phys.ethz.ch)
**Date:** 2026-04-13
**Status:** Implemented baseline harness exists under `tb/sim/` and `tb/uvm/`.
This document still carries planning structure from the original bring-up, but
the active simulator/runtime note and the checked-in harness paths below are
current. Migration rerun evidence on 2026-04-21: `make -C tb run_uvm_smoke`
passes on QuestaOne 2026.

This document specifies the UVM environment that realizes `DV_PLAN.md`. The plan's bucket names (B / E / X / R), CSR map (sections 3.*), interface list (section 2), coverage bins (section 5), and test catalog (section 6) are the source of truth and are not restated here except as cross-references.

---

## 1. Overview

The harness delivers a single-DUT UVM 1.2 environment that exercises
`runctl_mgmt_host` in standalone mode on the supported QuestaOne 2026 runtime.
Historical FSE Starter limitations are no longer the active simulator model for
this host. The checked-in harness still uses deterministic stimulus patterns
and lightweight coverage/accounting, but native DPI is available and used by
the current rerun path.

```
+---------------------------------------------------------------------+
|                     runctl_mgmt_host_env (uvm_env)                  |
|                                                                     |
|  +--------------+  +--------------+  +-------------------+          |
|  | synclink_agt |  | runctl_sink_ |  | upload_sink_agt   |          |
|  | (AVST sink   |  | agt (AVST    |  | (AVST source      |          |
|  |  driver,     |  |  source      |  |  ready-model,     |          |
|  |  monitor)    |  |  ready-model)|  |  monitor)         |          |
|  +------+-------+  +------+-------+  +---------+---------+          |
|         |                 |                    |                    |
|         | lvdspll_clk     | lvdspll_clk        | lvdspll_clk        |
|         v                 v                    v                    |
|  +---------------------------------------------------------------+  |
|  |                    runctl_mgmt_scoreboard                      |  |
|  |  - CSR shadow model         - log-FIFO sentence model          |  |
|  |  - runctl command predictor - upload ack predictor             |  |
|  |  - hard_reset mask model                                       |  |
|  +---------------------------------------------------------------+  |
|                           ^                                          |
|                           |                                          |
|  +--------------+         |                                          |
|  | csr_agt      |---------+                                          |
|  | (AVMM master,|        mm_clk                                      |
|  |  monitor)    |                                                    |
|  +--------------+                                                    |
|                                                                     |
|  +---------------------------------------------------------------+  |
|  |  Counter-based coverage collectors                            |  |
|  |  cov_csr | cov_cmd | cov_cross                                |  |
|  +---------------------------------------------------------------+  |
|                                                                     |
|  +---------------------------------------------------------------+  |
|  |  SVA bind modules                                             |  |
|  |  sva_synclink | sva_runctl | sva_upload | sva_csr | sva_cdc   |  |
|  +---------------------------------------------------------------+  |
+---------------------------------------------------------------------+
         ^                                        ^
         |                                        |
     mm_clk (150 MHz default)             lvdspll_clk (125 MHz)
     mm_reset (sync)                      lvdspll_reset (sync)
```

The env is instantiated inside `tb_top`. `tb_top` owns the two clock generators, the two reset generators, the DUT wrapper, and the `bind` statements for the SVA modules. Agents are connected to the DUT through four `virtual interface` handles passed via `uvm_config_db`.

---

## 2. Directory Layout

All paths are relative to the IP root (`run-control_mgmt/`). Most files listed
below now exist in the live tree; keep this section as a structure map rather
than as an implementation-gap claim.

```
tb/
  DV_PLAN.md                             # canonical plan (exists)
  DV_HARNESS.md                          # this document
  DV_BASIC.md / DV_EDGE.md / DV_CROSS.md / DV_ERROR.md  # planned per plan section 4
  Makefile                               # top-level compile/run targets
  sim/
    common/
      runctl_mgmt_pkg.sv                 # shared enums, command byte constants, helpers
      runctl_mgmt_addr_map.sv            # CSR word-address constants, bit-field offsets
      runctl_mgmt_ref_model.sv           # standalone reference model package
    runctl_mgmt_host_dut_wrapper.sv      # DUT instance wrapper w/ parameter overrides
    tb_top.sv                            # module top: clocks, resets, IFs, bind, run_test()
  uvm/
    runctl_mgmt_env_pkg.sv               # env package: includes all UVM sources
    runctl_mgmt_env.sv                   # uvm_env: builds agents/scoreboard/coverage
    runctl_mgmt_env_cfg.sv               # configuration object
    ifs/
      synclink_if.sv                     # AVST 9b+3b sink interface
      runctl_if.sv                       # AVST 9b source interface
      upload_if.sv                       # AVST 36b source interface
      csr_if.sv                          # AVMM 5b/32b slave interface
      reset_if.sv                        # dp_hard_reset / ct_hard_reset / ext_hard_reset observation
    agents/
      synclink_agent.sv                  # active driver on AVST sink
      synclink_driver.sv
      synclink_monitor.sv
      synclink_sequencer.sv
      synclink_txn.sv
      runctl_sink_agent.sv               # readyless monitor for runctl stream
      runctl_sink_driver.sv              # absent for readyless runctl
      runctl_sink_monitor.sv
      runctl_sink_txn.sv
      upload_sink_agent.sv               # AVST sink for upload stream
      upload_sink_driver.sv
      upload_sink_monitor.sv
      upload_sink_txn.sv
      csr_agent.sv                       # AVMM master agent (mm_clk)
      csr_driver.sv
      csr_monitor.sv
      csr_sequencer.sv
      csr_txn.sv
    scoreboard/
      runctl_mgmt_scoreboard.sv          # top scoreboard aggregator
      sb_csr_shadow.sv                   # CSR shadow + predictor
      sb_runctl_predictor.sv             # expected runctl fanout stream
      sb_upload_predictor.sv             # expected upload ack stream
      sb_log_sentence_predictor.sv       # 4-word log sentence model
      sb_hard_reset_model.sv             # mask-gated hard_reset model
    coverage/
      cov_csr.sv                         # CSR bin collectors (plan section 5.1)
      cov_cmd.sv                         # command bin collectors (plan section 5.2)
      cov_cross.sv                       # cross bin collectors (plan section 5.3)
    sequences/
      runctl_mgmt_seq_lib.sv             # sequence package
      basic_uid_seq.sv
      basic_meta_pages_seq.sv
      basic_scratch_rw_seq.sv
      basic_control_mask_rw_seq.sv
      basic_status_idle_seq.sv
      basic_cmd_run_prepare_seq.sv
      basic_cmd_run_sync_seq.sv
      basic_cmd_start_run_seq.sv
      basic_cmd_end_run_seq.sv
      basic_cmd_abort_run_seq.sv
      basic_cmd_reset_seq.sv
      basic_cmd_stop_reset_seq.sv
      basic_cmd_enable_seq.sv
      basic_cmd_disable_seq.sv
      basic_cmd_address_seq.sv
      basic_log_pop_seq.sv
      basic_rx_cmd_count_seq.sv
      basic_local_cmd_seq.sv
      basic_gts_snapshot_seq.sv
      basic_ack_symbols_seq.sv
      basic_log_status_empty_seq.sv
      edge_runctl_bp_seq.sv
      edge_upload_bp_seq.sv
      edge_log_fifo_seq.sv
      edge_mask_combo_seq.sv
      edge_soft_reset_seq.sv
      edge_log_flush_seq.sv
      edge_unknown_cmd_seq.sv
      edge_gts_wrap_seq.sv
      edge_address_no_fanout_seq.sv
      cross_csr_traffic_seq.sv
      cross_local_vs_synclink_seq.sv
      cross_dual_reset_seq.sv
      cross_long_random_seq.sv
      error_synclink_err_seq.sv
      error_truncated_payload_seq.sv
      error_mid_cmd_reset_seq.sv
      error_log_fifo_overflow_seq.sv
      error_csr_oob_seq.sv
    tests/
      runctl_mgmt_host_base_test.sv      # base test, owns env_cfg
      runctl_mgmt_host_basic_test.sv     # runs B-series sequences
      runctl_mgmt_host_edge_test.sv      # runs E-series sequences
      runctl_mgmt_host_cross_test.sv     # runs X-series sequences
      runctl_mgmt_host_error_test.sv     # runs R-series sequences
    sva/
      sva_synclink.sv
      sva_runctl.sv
      sva_upload.sv
      sva_csr.sv
      sva_cdc.sv
      sva_bind.sv                        # bind statements collected in one file
  scripts/
    run_uvm.sh                           # wrapper around make run
    run_uvm_case.sh                      # per-test runner
    merge_cov.sh                         # counter-collector log merge
```

---

## 3. DUT Wrapper

`tb/sim/runctl_mgmt_host_dut_wrapper.sv` instantiates `runctl_mgmt_host` and maps every DUT port onto the corresponding virtual interface signal. It exposes the DUT's parameter set through `module` parameters so that per-test overrides can be applied from `tb_top` via `defparam` or `#()` instantiation.

| Parameter | Purpose | Default | Sweep knob? |
|-----------|---------|---------|-------------|
| `UID`              | identity word at CSR 0x00 | `32'h52434D48` (`RCMH`) | no |
| `INSTANCE_ID`      | META page 3 payload | `32'h0` | yes (cross tests) |
| `VERSION`          | META page 0 payload | integration-defined | no |
| `LOG_FIFO_DEPTH`   | dcfifo write words | 128 | edge tests (near-full cases) |
| `RUN_START_ACK_SYMBOL` | K30.7 byte | `8'hFE` | yes |
| `RUN_END_ACK_SYMBOL`   | K29.7 byte | `8'hFD` | yes |

The wrapper binds:

| DUT port group | Interface | Clock |
|----------------|-----------|-------|
| `asi_synclink_*` | `synclink_if` | `lvdspll_clk` |
| `aso_runctl_*` | `runctl_if` | `lvdspll_clk` |
| `aso_upload_*` | `upload_if` | `lvdspll_clk` |
| `avs_csr_*` | `csr_if` | `mm_clk` |
| `dp_hard_reset`, `ct_hard_reset`, `ext_hard_reset` | `reset_if` | `lvdspll_clk` |
| `mm_clk`, `mm_reset` | direct | self |
| `lvdspll_clk`, `lvdspll_reset` | direct | self |

The wrapper also exposes a bundle of internal probe signals (recv FSM state, host FSM state, log FIFO write pointer) as `logic` outputs for SVA `bind` consumption. These are pure observation outputs and are only used in simulation.

---

## 4. Clock and Reset Generation

Two independent clock generators and two independent reset generators live in `tb_top.sv`. Both are fully parameterized at runtime through plusargs so that CDC stress tests can sweep phase and frequency.

### 4.1 Clocks

| Clock | Nominal | Plusarg for period (ps) | Plusarg for phase offset (ps) | Notes |
|-------|---------|-------------------------|-------------------------------|-------|
| `mm_clk`     | 150 MHz (period 6667 ps) | `+MM_PERIOD_PS=`     | `+MM_PHASE_PS=`     | arbitrary in plan's 100–200 MHz range |
| `lvdspll_clk`| 125 MHz (period 8000 ps) | `+LVDS_PERIOD_PS=`   | `+LVDS_PHASE_PS=`   | datapath clock |

Both clocks are generated by `always #(period/2) clk = ~clk;` style generators with a plusarg-seeded initial phase. A small jitter knob `+JITTER_PS=` optionally perturbs `lvdspll_clk` by ±jitter per edge using `mutrig_common_pkg::lcg_next`. No PLL model is used.

### 4.2 Resets

Both resets are synchronous active-high. Release order is controlled by the test through a pair of tasks on the env_cfg:

| Task | Effect |
|------|--------|
| `release_resets_lvds_first(delay_ns)` | `lvdspll_reset` drops first, `mm_reset` `delay_ns` later |
| `release_resets_mm_first(delay_ns)`   | `mm_reset` drops first, `lvdspll_reset` `delay_ns` later |
| `release_resets_simul()`              | both drop on the same simulator tick |
| `assert_resets_simul()`               | both asserted together (mid-test re-reset) |

This API backs tests `X008`, `X009`, `X010`, `R007`, `R008`, and covers cross bin `C6`.

### 4.3 Skew and frequency sweep

`tb_top.sv` exposes `+LVDS_PERIOD_PS` and `+MM_PERIOD_PS` so the cross-tests can iterate over `{100 MHz, 125 MHz, 150 MHz, 200 MHz}` for `mm_clk` against a fixed `lvdspll_clk`. This is the mechanism by which the harness stresses the mm↔lvds CDC described in plan section 1 (bullet list of CDC paths).

---

## 5. UVM Agents

Each agent follows the standard UVM 1.2 active-agent pattern (sequencer + driver + monitor) unless noted. Every monitor publishes through a `uvm_analysis_port`.

### 5.1 `synclink_agent` — AVST sink driver on `synclink_if`

Role: inject 9-bit AVST data frames into the DUT's synclink sink, carrying command bytes plus optional error injection. This interface has no `ready` (the DUT is a pure sink per plan section 2); the driver must respect nothing other than the clock edge.

**Transaction** (`synclink_txn`):

| Field | Width | Meaning |
|-------|-------|---------|
| `cmd_byte`      | 8b  | command opcode (0x10–0x14, 0x30–0x33, 0x40, or arbitrary for error tests) |
| `payload_q`     | byte queue | 0, 2, or 4 bytes, depending on command |
| `error_vec_q`   | 3-bit queue | per-beat error injection (`[2]=loss_sync, [1]=parity, [0]=decode`) |
| `k_flag_q`      | bit queue   | per-beat k-flag for the 9th bit |
| `inter_beat_gap`| int  | idle cycles between beats (stalls the driver) |

The driver walks the queues and drives one AVST beat per lvdspll_clk edge. Because the DUT never backpressures, the protocol rule enforced is simply "data stable when valid" — easy to maintain because the driver holds each beat for one cycle. A companion monitor watches the interface to publish accepted beats for scoreboard correlation.

### 5.2 `runctl_sink_agent` — readyless AVST monitor on `runctl_if`

Role: observe the runctl output stream. There is no `ready` signal: every `valid`
cycle is a broadcast beat and downstream agents cannot backpressure the host.

The monitor captures every `valid` cycle and publishes one transaction per
broadcast beat (`runctl_sink_txn { logic [8:0] data; bit k_flag; }`). Scoreboard
uses this stream to confirm that every expected fanout byte arrived in order and
that `CMD_ADDRESS` remains suppressed.

### 5.3 `upload_sink_agent` — AVST sink on `upload_if`

Role: terminate the 36-bit upload stream and verify ack packet format.

**Ready models:** same enum as the runctl agent (`RDY_ALWAYS`, `RDY_LAT_N`, `RDY_TOGGLE_1`, `RDY_HELD_LOW`, `RDY_RANDOM`).

**Transaction** (`upload_sink_txn`):

| Field | Width | Meaning |
|-------|-------|---------|
| `data`      | 36b  | `{datak[3:0], data[31:0]}` |
| `sop`, `eop`| 1b   | Avalon-ST framing |
| `word_index`| int  | index within packet (monitor-assigned) |

The monitor reassembles complete packets between `sop` and `eop`. The scoreboard's upload predictor asserts that:

- `RUN_PREPARE` (0x10) produces a packet whose header carries the K30.7 symbol (`RUN_START_ACK_SYMBOL`, default 0xFE) and whose tail packs the 32-bit run number (exact bit placement deferred to the RTL spec; scoreboard reads it from the CSR shadow).
- `END_RUN` (0x13) produces a packet whose header carries the K29.7 symbol (`RUN_END_ACK_SYMBOL`, default 0xFD) with no payload tail.
- No other command class produces an upload packet.

### 5.4 `csr_agent` — AVMM master on `csr_if`

Role: drive and observe the 5-bit address, 32-bit data CSR slave on `mm_clk`.

**Driver task API:**

| Task | Behavior |
|------|----------|
| `csr_write32(addr, data)`         | 1 mm_clk cycle, respects `waitrequest` even though plan declares 0 |
| `csr_read32(addr, var data)`      | asserts `read`, samples `readdata` on the 2nd cycle (1-cycle read latency per plan) |
| `csr_read_expect(addr, exp, mask)`| wrapper calling `csr_read32` then comparing `(readdata & mask) == (exp & mask)` |
| `csr_burst_read(addr, n, q)`      | repeated single-beat reads (AVMM has no burst on this slave) |

The monitor publishes every observed `read` or `write` transfer as a `csr_txn` so that `cov_csr` and the CSR shadow scoreboard can consume it. All CSR activity is mm_clk-domain only.

---

## 6. Scoreboards

The top-level `runctl_mgmt_scoreboard` is a `uvm_scoreboard` that owns five sub-model components and feeds them through analysis-export hooks. Every sub-model is a `uvm_component` to keep the class hierarchy flat and to let each one own its own `report_phase`.

| Sub-model | File | Inputs | Checks |
|-----------|------|--------|--------|
| CSR shadow            | `sb_csr_shadow.sv`            | csr_txn, synclink_txn, upload_sink_txn, reset_if samples | mirrors every writable field; checks each CSR read against the shadow. Models counter saturation (`RX_CMD_COUNT`, `RX_ERR_COUNT`), META page selector, SCRATCH, LOCAL_CMD echo, FPGA_ADDRESS latch including the `[31]` sticky bit, RUN_NUMBER, RESET_MASK assert/release halves, atomic `GTS_L`/`GTS_H` latch on GTS_L read. |
| runctl fanout predictor | `sb_runctl_predictor.sv`      | synclink_txn (accepted), csr_txn (LOCAL_CMD writes), runctl_sink_txn | for every accepted command that should fan out (plan section 3.7), push the expected 9-bit word onto an expected queue; pop on observed runctl beat. Mismatch or stale queue at end-of-test = `UVM_ERROR`. |
| upload ack predictor    | `sb_upload_predictor.sv`      | synclink_txn, csr_txn, upload_sink_txn | verifies RUN_PREPARE emits a single ack packet with `datak` bit set for the K30.7 header and run-number tail; END_RUN emits a single K29.7 ack. Any other command class must produce zero upload packets. |
| log sentence predictor  | `sb_log_sentence_predictor.sv`| synclink_txn, csr_txn (CONTROL, LOG_POP) | predicts the 4-word log sentence per plan section 3.6 from observed recv/host events, stores them in a FIFO, and checks each `LOG_POP` read against the head of the predicted FIFO. Handles `CONTROL.soft_reset` and `CONTROL.log_flush` semantics. |
| hard_reset model        | `sb_hard_reset_model.sv`      | synclink_txn, csr_txn (CONTROL.rst_mask_*), reset_if | on CMD_RESET / CMD_STOP_RESET, predicts local `dp_hard_reset` / `ct_hard_reset` polarity after the CONTROL mask is applied and predicts `ext_hard_reset` as a bounded exported subsystem reset pulse; compares against the monitored reset outputs. |

The scoreboard subscribes to analysis ports via `uvm_analysis_imp_decl` helpers so that each monitor feeds multiple sub-models without cloning transactions.

---

## 7. Coverage Collectors

All coverage is counter-based. Each collector is a `uvm_component` that lives in `tb/uvm/coverage/`, listens to one or more monitor analysis ports, maintains integer counter arrays, and emits results from `report_phase`. No `covergroup`, no `cross`, no `rand`. Bin lists below come directly from `DV_PLAN.md` section 5 and must stay in sync with that source.

| Collector | File | Bin groups (plan source) | Inputs |
|-----------|------|--------------------------|--------|
| `cov_csr`   | `cov_csr.sv`   | plan 5.1: `csr_addr_write` (4), `csr_addr_read` (21), `csr_writeread_pair` (4), `meta_page` (4), `scratch_pattern` (4), `control_writeable_bits` (4), `control_mask_combo` (4) | csr_txn analysis port |
| `cov_cmd`   | `cov_cmd.sv`   | plan 5.2: `cmd_byte_synclink` (10), `cmd_byte_local` (10), `cmd_byte_unknown` (1), `cmd_payload_runprep` (3), `cmd_payload_reset` (3), `cmd_payload_stop_reset` (3), `cmd_payload_address` (3), `upload_ack_class` (2) | synclink_txn, csr_txn (LOCAL_CMD), upload_sink_txn |
| `cov_cross` | `cov_cross.sv` | plan 5.3: C1 (30) × C2 (4) × C3 (12) × C4 (15) × C5 (8) × C6 (3) × C7 (30), 102 cells total | every monitor port plus an `env_state_probe` that snapshots recv_state / host_state via the wrapper's internal signals |

Each bin group is stored as `int unsigned <name>_hits[N]`. `sample_*()` methods are invoked from `write_*()` analysis callbacks. `report_coverage()` prints a single-line summary per group and, for every zero bin, emits `UNCOVERED: <group>[<idx>]`. Any non-zero `UNCOVERED` count at end-of-regression fails signoff (plan section 7).

Total bin count, for cross-check with plan section 5: 27 (CSR) + 38 (command) + 102 (cross) = 167.

---

## 8. Randomization Strategy

The harness uses only the LCG PRNG from `mutrig_common_pkg` (`lcg_next(state) -> logic[31:0]`). No `rand`, no `constraint`.

| Element | Mechanism |
|---------|-----------|
| Seeding | Plusarg `+SEED=<uint32>` consumed in `runctl_mgmt_host_base_test::start_of_simulation`. Seed is stored on `env_cfg.seed` and logged to the transcript (`UVM_INFO runctl_mgmt_host_base_test "SEED=0x%08x"`). |
| Per-agent streams | Each agent takes an independent 32-bit state seeded from `env_cfg.seed` with a fixed offset so that replays with the same `+SEED` reproduce exactly. |
| Payload picking | `lcg_next()` modulo bucket-count selects among edge-pattern buckets. Example: for `cmd_payload_runprep` the sequence picks one of `{0, mid, 0xFFFFFFFF}` by `lcg_next() % 3`. |
| Edge bin closure | Buckets are defined as exactly the plan coverage bins, so uniform bucket selection with enough iterations guarantees bin hits. Cross tests iterate the outer product explicitly (nested `for` loops over axes) rather than relying on probability. |
| Reproducibility | `+SEED=` and `+UVM_TESTNAME=` together uniquely determine the simulation. Failed tests record the seed in the final error report. |

---

## 9. Assertions

SVA modules live under `tb/uvm/sva/`. Each module is `bind`-ed in `sva_bind.sv`. All assertions call `$error` (not `$fatal`) so the scoreboard can also flag the mismatch.

### 9.1 `sva_synclink`

| ID | Property |
|----|----------|
| SL01 | AVST data stable across the cycle it is presented (pure sink, no ready) |
| SL02 | `data[8]` (k-flag) never X/Z outside reset |
| SL03 | `error[2:0]` never X/Z outside reset |

### 9.2 `sva_runctl`

| ID | Property |
|----|----------|
| RC01 | `valid` does not deassert while `ready=0` (AVST rule) |
| RC02 | `data[8:0]` stable while `valid=1 && ready=0` |
| RC03 | No `valid` during `lvdspll_reset` |

### 9.3 `sva_upload`

| ID | Property |
|----|----------|
| UL01 | `valid` stable while `ready=0` |
| UL02 | `data[35:0]`, `sop`, `eop` stable while `valid=1 && ready=0` |
| UL03 | `sop` and `eop` paired — no nested packet |
| UL04 | For RUN_PREPARE ack, header beat has `datak[3:0]` matching K30.7 slot |
| UL05 | For END_RUN ack, header beat has `datak[3:0]` matching K29.7 slot |

### 9.4 `sva_csr`

| ID | Property |
|----|----------|
| CR01 | `waitrequest == 0` always (plan section 2 declares 1-cycle read latency, no waitrequest) |
| CR02 | `readdata` has no X/Z after reset deasserts |
| CR03 | Read latency is exactly 1 mm_clk cycle |
| CR04 | `read` and `write` never both high in the same cycle |

### 9.5 `sva_cdc`

| ID | Property |
|----|----------|
| CDC01 | Local-cmd toggle handshake: request toggle stable for ≥2 destination cycles before ack toggle changes |
| CDC02 | GTS gray-coded CDC Hamming distance ≤1 between adjacent samples |
| CDC03 | Status snapshot toggle request → response ack within bounded cycles |
| CDC04 | `dp_hard_reset` / `ct_hard_reset` / `ext_hard_reset` only change after a lvdspll_clk edge (no combinational glitch) |

Reset-while-running guard: every property is qualified with `disable iff (lvdspll_reset || mm_reset)` or the appropriate domain reset so that reset pulses never trip the SVA.

---

## 10. Test Base Class and Test List

`runctl_mgmt_host_base_test` is a `uvm_test` that:

1. Builds an `runctl_mgmt_env` and an `runctl_mgmt_env_cfg`.
2. Reads plusargs: `+SEED=`, `+MM_PERIOD_PS=`, `+LVDS_PERIOD_PS=`, `+RUNCTL_RDY_MODE=`, `+UPLOAD_RDY_MODE=`, `+RESET_ORDER=`.
3. Installs the env_cfg in `uvm_config_db`.
4. Publishes a virtual sequencer (`v_seqr`) that aggregates the four agent sequencers so that sequences can multicast.
5. Exposes a `run_phase` that releases resets according to `env_cfg.reset_order`, then kicks off the test's sequence library.

Derived tests each pick a sequence library from `tb/uvm/sequences/`. One test per bucket; bucket granularity is deliberate so that regression can select `+UVM_TESTNAME=runctl_mgmt_host_basic_test +SEQ=basic_uid_seq` to run a single case.

Current repository state note:
the bucket-library split below is still the authored target architecture, but
the implemented direct standalone tests in this tree today are
`runctl_mgmt_host_smoke_test`,
`runctl_mgmt_host_synclink_cmd_matrix_test`, and
`runctl_mgmt_host_local_cmd_backpressure_test`. The last one is the canonical
direct reproducer for `BUG-001-R` and covers the held `LOCAL_CMD`
busy-clear / waitrequest-release subcase closest to plan items `E097` and
`E098`.

| Test class | DV_PLAN bucket | Sequence library driver |
|------------|----------------|-------------------------|
| `runctl_mgmt_host_basic_test` | B-series (plan 6.1)  | runs one `basic_*_seq` per `+SEQ=` arg; defaults to full B-series chain |
| `runctl_mgmt_host_edge_test`  | E-series (plan 6.2)  | runs `edge_*_seq` chain |
| `runctl_mgmt_host_cross_test` | X-series (plan 6.3)  | runs `cross_*_seq` chain |
| `runctl_mgmt_host_error_test` | R-series (plan 6.4)  | runs `error_*_seq` chain |

A top-level regression script iterates `+SEQ` across every sequence in the library and collects counter-coverage reports from the log files. All 74 IDs listed in plan section 6 map 1-to-1 to sequences (see traceability matrix, section 13 below).

---

## 11. Build and Run

### 11.1 Makefile sketch

Top-level `tb/Makefile` targets (names match `histogram_statistics/tb/Makefile`):

| Target | Action |
|--------|--------|
| `compile`            | `vlog`/`vcom` of RTL + UVM + TB |
| `run TEST=<t>`       | `vsim -c` with `+UVM_TESTNAME=<t>` |
| `run_vcd TEST=<t>`   | same plus VCD dump |
| `run_cov TEST=<t>`   | same plus `-coverage` and `.ucdb` save |
| `run_all`            | iterate basic / edge / cross / error suites |
| `clean`              | remove work libs, transcripts, ucdb |

License resolution uses the pattern from `/home/yifeng/CLAUDE.md`: prefer local Questa FSE license, fall back to ETH Mentor floating.

### 11.2 Compile flags

UVM package compiled with: `+define+UVM_NO_DPI +incdir+$(UVM_HOME)/src`.

DUT / TB compiled with: `-sv -mfcu -timescale=1ps/1ps`. Suppressions match histogram_statistics: `-suppress 19 -suppress 3009 -suppress 3473` for the common harmless warnings.

### 11.3 Simulate flags

```
vsim -c -nodpiexports \
     -suppress 19 -suppress 3009 -suppress 3473 \
     -voptargs=+acc \
     +UVM_TESTNAME=runctl_mgmt_host_basic_test \
     +SEED=0xdeadbeef \
     +MM_PERIOD_PS=6667 \
     +LVDS_PERIOD_PS=8000 \
     tb_top
```

`-nodpiexports` is mandatory under Questa FSE (no DPI linker available on this system). UVM is built with `UVM_NO_DPI` for the same reason.

### 11.4 Waveform save

On failure, `run_vcd` dumps `tb/waves/generated/<test>_<seed>.vcd`. A GTKWave save template under `tb/waves/` groups the scopes that matter (synclink, runctl, upload, csr, FSM states, CDC toggles). The full phase-4 waveform publication flow follows `histogram_statistics/tb/DV_HARNESS.md` section 8.1 once signoff begins.

---

## 12. CDC Validation Approach

The `mm_clk` / `lvdspll_clk` asynchrony is the single largest risk surface for this DUT (plan section 1 explicitly lists toggle handshake, gray-coded gts CDC, atomic GTS snapshot, status snapshot toggle). The harness stresses CDC in three independent ways:

1. **Phase sweep.** `+LVDS_PHASE_PS=` and `+MM_PHASE_PS=` set the initial clock phase; a regression loop runs the cross test suite at `{0, 250, 500, 1000, 2000}` ps `mm_clk` offsets. The LCG-driven jitter option adds a second-order perturbation.
2. **Frequency-ratio sweep.** Cross tests iterate `mm_clk` periods across `{5000, 6667, 8000, 10000}` ps (200, 150, 125, 100 MHz) against the fixed `lvdspll_clk = 8000 ps`. Every combination must pass the counter-coverage and scoreboard checks.
3. **Per-reset independent release.** Tests X008/X009/X010 (plan 6.3) exercise lvds-first / mm-first / simultaneous reset release. R007/R008 exercise mid-command reset on each domain independently. Cross bin `C6` requires at least one hit per ordering.

CDC correctness is checked in two layers: `sva_cdc` at the cycle level (no metastable handshake), and the scoreboard sub-models at the value level (every CSR readback is self-consistent, GTS_H always matches the upper half latched at the GTS_L read).

---

## 13. Traceability Matrix

Every test ID in `DV_PLAN.md` section 6 maps to exactly one sequence class under `tb/uvm/sequences/`. The mapping is flat; more complex tests may reuse building-block subsequences internally.

### 13.1 DV_BASIC (plan section 6.1)

| Plan ID | Sequence |
|---------|----------|
| B001_uid_read              | `basic_uid_seq` |
| B002_uid_write_ignored     | `basic_uid_seq` (write + readback) |
| B003_meta_pages            | `basic_meta_pages_seq` |
| B004_scratch_rw            | `basic_scratch_rw_seq` |
| B005_control_mask_rw       | `basic_control_mask_rw_seq` |
| B006_status_idle_after_reset | `basic_status_idle_seq` |
| B007_synclink_run_prepare  | `basic_cmd_run_prepare_seq` |
| B008_synclink_run_sync     | `basic_cmd_run_sync_seq` |
| B009_synclink_start_run    | `basic_cmd_start_run_seq` |
| B010_synclink_end_run      | `basic_cmd_end_run_seq` |
| B011_synclink_abort_run    | `basic_cmd_abort_run_seq` |
| B012_synclink_reset        | `basic_cmd_reset_seq` |
| B013_synclink_stop_reset   | `basic_cmd_stop_reset_seq` |
| B014_synclink_enable       | `basic_cmd_enable_seq` |
| B015_synclink_disable      | `basic_cmd_disable_seq` |
| B016_synclink_address      | `basic_cmd_address_seq` |
| B017_log_pop_4words        | `basic_log_pop_seq` |
| B018_rx_cmd_count          | `basic_rx_cmd_count_seq` |
| B019_local_cmd_basic       | `basic_local_cmd_seq` |
| B020_gts_snapshot          | `basic_gts_snapshot_seq` |
| B021_ack_symbols_default   | `basic_ack_symbols_seq` |
| B022_log_status_empty      | `basic_log_status_empty_seq` |

### 13.2 DV_EDGE (plan section 6.2)

| Plan ID | Sequence |
|---------|----------|
| E001_runctl_readyless_broadcast | `edge_runctl_readyless_seq` |
| E002_upload_ready_held_low      | `edge_upload_bp_seq` (mode=HELD_LOW) |
| E003_back_to_back_cmds          | `edge_runctl_readyless_seq` (burst) |
| E004_log_fifo_near_full         | `edge_log_fifo_seq` (fill) |
| E005_log_pop_burst              | `edge_log_fifo_seq` (drain) |
| E006_meta_invalid_page          | `basic_meta_pages_seq` (extended) |
| E007_control_mask_dp_only       | `edge_mask_combo_seq` (10) |
| E008_control_mask_ct_only       | `edge_mask_combo_seq` (01) |
| E009_control_mask_both          | `edge_mask_combo_seq` (11) |
| E010_gts_wrap                   | `edge_gts_wrap_seq` |
| E011_address_no_fanout          | `edge_address_no_fanout_seq` |
| E012_runctl_readyless_burst     | `edge_runctl_readyless_seq` (long burst) |
| E013_local_cmd_busy_block       | `basic_local_cmd_seq` (two writes, no poll) |
| E014_soft_reset_idle            | `edge_soft_reset_seq` |
| E015_log_flush                  | `edge_log_flush_seq` |
| E016_rx_err_count_increment     | `error_synclink_err_seq` (single parity) |
| E017_unknown_command            | `edge_unknown_cmd_seq` |
| E018_atomic_gts_two_readers     | `basic_gts_snapshot_seq` (interleaved) |
| E019_status_state_encoding      | `edge_payload_stall_seq` (RX_PAYLOAD status poll) |
| E020_runctl_no_ready_port       | `edge_runctl_readyless_elab_seq` |

### 13.3 DV_CROSS (plan section 6.3)

| Plan ID | Sequence |
|---------|----------|
| X001_csr_traffic_during_cmd    | `cross_csr_traffic_seq` (read mix) |
| X002_csr_writes_during_cmd     | `cross_csr_traffic_seq` (write mix) |
| X003_local_cmd_vs_synclink     | `cross_local_vs_synclink_seq` |
| X004_mask_combo_sweep          | `edge_mask_combo_seq` (full 4×2 sweep) |
| X005_log_fill_drain_mix        | `edge_log_fifo_seq` (mixed fill/drain) |
| X006_upload_backpressure_mix   | `edge_upload_bp_seq` (sweep across 10 cmd classes × 3 modes) |
| X007_runctl_latency_sweep      | `edge_runctl_bp_seq` (sweep) |
| X008_dual_reset_lvds_first     | `cross_dual_reset_seq` (lvds_first) |
| X009_dual_reset_mm_first       | `cross_dual_reset_seq` (mm_first) |
| X010_dual_reset_simul          | `cross_dual_reset_seq` (simul) |
| X011_local_cmd_phase_mix       | `cross_local_vs_synclink_seq` (phased) |
| X012_long_random_run           | `cross_long_random_seq` |
| X013_log_pop_burst_during_cmd  | `cross_csr_traffic_seq` (LOG_POP burst + cmds) |
| X014_meta_sweep_during_cmd     | `cross_csr_traffic_seq` (META sweep) |
| X015_scratch_pattern_during_cmd| `cross_csr_traffic_seq` (SCRATCH patterns) |

### 13.4 DV_ERROR (plan section 6.4)

| Plan ID | Sequence |
|---------|----------|
| R001_synclink_parity_error   | `error_synclink_err_seq` (error[1]) |
| R002_synclink_decode_error   | `error_synclink_err_seq` (error[0]) |
| R003_synclink_loss_sync      | `error_synclink_err_seq` (error[2]) |
| R004_unknown_cmd_byte        | `edge_unknown_cmd_seq` |
| R005_truncated_run_prepare   | `error_truncated_payload_seq` (RUN_PREPARE) |
| R006_truncated_reset         | `error_truncated_payload_seq` (CMD_RESET) |
| R007_mid_cmd_lvdspll_reset   | `error_mid_cmd_reset_seq` (lvds) |
| R008_mid_cmd_mm_reset        | `error_mid_cmd_reset_seq` (mm) |
| R009_soft_reset_during_cmd   | `edge_soft_reset_seq` (mid-cmd) |
| R010_log_flush_during_cmd    | `edge_log_flush_seq` (mid-cmd) |
| R011_local_cmd_during_busy   | `basic_local_cmd_seq` (back-to-back) |
| R012_runctl_ready_removed    | `error_runctl_ready_removed_seq` |
| R013_upload_ready_stuck_low  | `edge_upload_bp_seq` (HELD_LOW, 10000 cycles) |
| R014_log_fifo_full_overflow  | `error_log_fifo_overflow_seq` |
| R015_csr_addr_oob            | `error_csr_oob_seq` |
| R016_simultaneous_cmd_and_err| `error_synclink_err_seq` (every-other-byte) |
| R017_recovery_after_loss_sync| `error_synclink_err_seq` (R003 + clean tail) |

Total: 22 + 20 + 15 + 17 = 74 sequences, one per plan ID. Sequences marked with an `(extended)` or a mode parameter are parametric; the test runner passes the mode via plusarg `+SEQ_MODE=`.

---

## 14. References

- `tb/DV_PLAN.md` — canonical plan, source of truth for every bucket, bin, and ID cited above
- `histogram_statistics/tb/DV_HARNESS.md` — structural template (directory layout, Makefile, waveform publication)
- `slow-control_hub/tb/DV_HARNESS.md` — multi-interface / scoreboard reference
- `/home/yifeng/CLAUDE.md` — Questa FSE constraints, license setup, LCG PRNG policy
- `mutrig_common_pkg::lcg_next` — the only PRNG used in this harness
