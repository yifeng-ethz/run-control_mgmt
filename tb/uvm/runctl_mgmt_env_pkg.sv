`timescale 1ps/1ps

package runctl_mgmt_env_pkg;
  import uvm_pkg::*;
  import runctl_mgmt_pkg::*;
  `include "uvm_macros.svh"

  `uvm_analysis_imp_decl(_runctl)
  `uvm_analysis_imp_decl(_upload)
  `uvm_analysis_imp_decl(_reset)

  class runctl_mgmt_env_cfg extends uvm_object;
    `uvm_object_utils(runctl_mgmt_env_cfg)

    int unsigned csr_timeout_cycles = 16;
    int unsigned obs_timeout_cycles = 64;

    function new(string name = "runctl_mgmt_env_cfg");
      super.new(name);
    endfunction
  endclass

  class runctl_synclink_item extends uvm_sequence_item;
    `uvm_object_utils(runctl_synclink_item)

    byte unsigned cmd_byte;
    byte unsigned payload_q[$];
    bit [2:0]     error_q[$];
    bit           use_raw_symbols;
    logic [8:0]   raw_symbol_q[$];
    int unsigned  tail_idle_cycles = 1;

    function new(string name = "runctl_synclink_item");
      super.new(name);
    endfunction
  endclass

  class runctl_csr_item extends uvm_sequence_item;
    `uvm_object_utils(runctl_csr_item)

    bit        is_write;
    bit [4:0]  address;
    bit [31:0] writedata;
    bit [31:0] readdata;

    function new(string name = "runctl_csr_item");
      super.new(name);
    endfunction
  endclass

  class runctl_runctl_obs extends uvm_sequence_item;
    `uvm_object_utils(runctl_runctl_obs)

    logic [8:0] data;
    time        sample_time_ps;

    function new(string name = "runctl_runctl_obs");
      super.new(name);
    endfunction
  endclass

  class runctl_upload_obs extends uvm_sequence_item;
    `uvm_object_utils(runctl_upload_obs)

    logic [35:0] data;
    logic        startofpacket;
    logic        endofpacket;
    time         sample_time_ps;

    function new(string name = "runctl_upload_obs");
      super.new(name);
    endfunction
  endclass

  class runctl_reset_obs extends uvm_sequence_item;
    `uvm_object_utils(runctl_reset_obs)

    bit  dp_hard_reset;
    bit  ct_hard_reset;
    bit  ext_hard_reset;
    time sample_time_ps;

    function new(string name = "runctl_reset_obs");
      super.new(name);
    endfunction
  endclass

  class runctl_synclink_sequencer extends uvm_sequencer #(runctl_synclink_item);
    `uvm_component_utils(runctl_synclink_sequencer)

    function new(string name = "runctl_synclink_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class runctl_csr_sequencer extends uvm_sequencer #(runctl_csr_item);
    `uvm_component_utils(runctl_csr_sequencer)

    function new(string name = "runctl_csr_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class runctl_synclink_driver extends uvm_driver #(runctl_synclink_item);
    `uvm_component_utils(runctl_synclink_driver)

    virtual synclink_if.drv vif;

    function new(string name = "runctl_synclink_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual synclink_if.drv)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_type_name(), "Missing synclink_if.drv")
      end
    endfunction

    task automatic drive_item(runctl_synclink_item item);
      if (item.use_raw_symbols && item.raw_symbol_q.size() > 0) begin
        foreach (item.raw_symbol_q[idx]) begin
          vif.data = item.raw_symbol_q[idx];
          if (idx < item.error_q.size())
            vif.error = item.error_q[idx];
          else
            vif.error = 3'b000;
          @(posedge vif.clk);
        end
      end else begin
        vif.data  = {1'b0, item.cmd_byte};
        if (item.error_q.size() > 0)
          vif.error = item.error_q[0];
        else
          vif.error = 3'b000;
        @(posedge vif.clk);

        foreach (item.payload_q[idx]) begin
          vif.data = {1'b0, item.payload_q[idx]};
          if ((idx + 1) < item.error_q.size())
            vif.error = item.error_q[idx + 1];
          else
            vif.error = 3'b000;
          @(posedge vif.clk);
        end
      end

      vif.data  = SYNCLINK_IDLE_COMMA;
      vif.error = '0;
      repeat (item.tail_idle_cycles) @(posedge vif.clk);
    endtask

    task run_phase(uvm_phase phase);
      vif.data  = SYNCLINK_IDLE_COMMA;
      vif.error = '0;
      forever begin
        seq_item_port.get_next_item(req);
        drive_item(req);
        seq_item_port.item_done();
      end
    endtask
  endclass

  class runctl_csr_driver extends uvm_driver #(runctl_csr_item);
    `uvm_component_utils(runctl_csr_driver)

    virtual csr_if.drv vif;

    function new(string name = "runctl_csr_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual csr_if.drv)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_type_name(), "Missing csr_if.drv")
      end
    endfunction

    task automatic reset_bus();
      vif.address   = '0;
      vif.read      = 1'b0;
      vif.write     = 1'b0;
      vif.writedata = '0;
    endtask

    task automatic drive_item(runctl_csr_item item);
      vif.address   = item.address;
      vif.writedata = item.writedata;
      vif.read      = !item.is_write;
      vif.write     = item.is_write;

      do begin
        @(posedge vif.clk);
      end while (vif.waitrequest !== 1'b0);

      if (!item.is_write)
        item.readdata = vif.readdata;

      reset_bus();
      @(posedge vif.clk);
    endtask

    task run_phase(uvm_phase phase);
      reset_bus();
      forever begin
        seq_item_port.get_next_item(req);
        drive_item(req);
        seq_item_port.item_done();
      end
    endtask
  endclass

  class runctl_synclink_agent extends uvm_agent;
    `uvm_component_utils(runctl_synclink_agent)

    runctl_synclink_sequencer seqr;
    runctl_synclink_driver    driver;

    function new(string name = "runctl_synclink_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      seqr   = runctl_synclink_sequencer::type_id::create("seqr", this);
      driver = runctl_synclink_driver::type_id::create("driver", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  class runctl_csr_agent extends uvm_agent;
    `uvm_component_utils(runctl_csr_agent)

    runctl_csr_sequencer seqr;
    runctl_csr_driver    driver;

    function new(string name = "runctl_csr_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      seqr   = runctl_csr_sequencer::type_id::create("seqr", this);
      driver = runctl_csr_driver::type_id::create("driver", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  class runctl_sink_monitor extends uvm_monitor;
    `uvm_component_utils(runctl_sink_monitor)

    virtual runctl_if.mon vif;
    uvm_analysis_port #(runctl_runctl_obs) ap;

    function new(string name = "runctl_sink_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual runctl_if.mon)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_type_name(), "Missing runctl_if.mon")
      end
    endfunction

    task run_phase(uvm_phase phase);
      runctl_runctl_obs obs;
      forever begin
        @(posedge vif.clk);
        if (vif.valid) begin
          obs                = runctl_runctl_obs::type_id::create("obs");
          obs.data           = vif.data;
          obs.sample_time_ps = $time;
          ap.write(obs);
        end
      end
    endtask
  endclass

  class upload_sink_monitor extends uvm_monitor;
    `uvm_component_utils(upload_sink_monitor)

    virtual upload_if.mon vif;
    uvm_analysis_port #(runctl_upload_obs) ap;

    function new(string name = "upload_sink_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual upload_if.mon)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_type_name(), "Missing upload_if.mon")
      end
    endfunction

    task run_phase(uvm_phase phase);
      runctl_upload_obs obs;
      forever begin
        @(posedge vif.clk);
        if (vif.valid && vif.ready) begin
          obs                  = runctl_upload_obs::type_id::create("obs");
          obs.data             = vif.data;
          obs.startofpacket    = vif.startofpacket;
          obs.endofpacket      = vif.endofpacket;
          obs.sample_time_ps   = $time;
          ap.write(obs);
        end
      end
    endtask
  endclass

  class reset_monitor extends uvm_monitor;
    `uvm_component_utils(reset_monitor)

    virtual reset_if.mon vif;
    uvm_analysis_port #(runctl_reset_obs) ap;

    function new(string name = "reset_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual reset_if.mon)::get(this, "", "vif", vif)) begin
        `uvm_fatal(get_type_name(), "Missing reset_if.mon")
      end
    endfunction

    task run_phase(uvm_phase phase);
      runctl_reset_obs obs;
      bit first_sample = 1'b1;
      bit last_dp;
      bit last_ct;
      bit last_ext;

      forever begin
        @(posedge vif.clk);
        if (first_sample ||
            vif.dp_hard_reset  != last_dp ||
            vif.ct_hard_reset  != last_ct ||
            vif.ext_hard_reset != last_ext) begin
          obs                = runctl_reset_obs::type_id::create("obs");
          obs.dp_hard_reset  = vif.dp_hard_reset;
          obs.ct_hard_reset  = vif.ct_hard_reset;
          obs.ext_hard_reset = vif.ext_hard_reset;
          obs.sample_time_ps = $time;
          ap.write(obs);
          last_dp            = vif.dp_hard_reset;
          last_ct            = vif.ct_hard_reset;
          last_ext           = vif.ext_hard_reset;
          first_sample       = 1'b0;
        end
      end
    endtask
  endclass

  class runctl_scoreboard extends uvm_component;
    `uvm_component_utils(runctl_scoreboard)

    uvm_analysis_imp_runctl #(runctl_runctl_obs, runctl_scoreboard) runctl_imp;
    uvm_analysis_imp_upload #(runctl_upload_obs, runctl_scoreboard) upload_imp;
    uvm_analysis_imp_reset  #(runctl_reset_obs,  runctl_scoreboard) reset_imp;

    runctl_runctl_obs runctl_q[$];
    runctl_upload_obs upload_q[$];
    runctl_reset_obs  reset_q[$];

    event runctl_ev;
    event upload_ev;
    event reset_ev;

    int unsigned runctl_count;
    int unsigned upload_count;
    int unsigned reset_count;

    function new(string name = "runctl_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      runctl_imp = new("runctl_imp", this);
      upload_imp = new("upload_imp", this);
      reset_imp  = new("reset_imp", this);
    endfunction

    function void write_runctl(runctl_runctl_obs t);
      runctl_runctl_obs clone_obs;
      clone_obs = runctl_runctl_obs::type_id::create("clone_obs");
      clone_obs.data = t.data;
      clone_obs.sample_time_ps = t.sample_time_ps;
      runctl_count++;
      runctl_q.push_back(clone_obs);
      -> runctl_ev;
    endfunction

    function void write_upload(runctl_upload_obs t);
      runctl_upload_obs clone_obs;
      clone_obs = runctl_upload_obs::type_id::create("clone_obs");
      clone_obs.data = t.data;
      clone_obs.startofpacket = t.startofpacket;
      clone_obs.endofpacket = t.endofpacket;
      clone_obs.sample_time_ps = t.sample_time_ps;
      upload_count++;
      upload_q.push_back(clone_obs);
      -> upload_ev;
    endfunction

    function void write_reset(runctl_reset_obs t);
      runctl_reset_obs clone_obs;
      clone_obs = runctl_reset_obs::type_id::create("clone_obs");
      clone_obs.dp_hard_reset = t.dp_hard_reset;
      clone_obs.ct_hard_reset = t.ct_hard_reset;
      clone_obs.ext_hard_reset = t.ext_hard_reset;
      clone_obs.sample_time_ps = t.sample_time_ps;
      reset_count++;
      reset_q.push_back(clone_obs);
      -> reset_ev;
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info(get_type_name(),
                $sformatf("Observed runctl=%0d upload=%0d reset_events=%0d",
                          runctl_count, upload_count, reset_count),
                UVM_LOW)
    endfunction
  endclass

  class runctl_mgmt_env extends uvm_env;
    `uvm_component_utils(runctl_mgmt_env)

    runctl_mgmt_env_cfg cfg;
    runctl_synclink_agent synclink_agent;
    runctl_csr_agent      csr_agent;
    runctl_sink_monitor   runctl_monitor_h;
    upload_sink_monitor   upload_monitor_h;
    reset_monitor         reset_monitor_h;
    runctl_scoreboard     sb;

    function new(string name = "runctl_mgmt_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(runctl_mgmt_env_cfg)::get(this, "", "cfg", cfg)) begin
        cfg = runctl_mgmt_env_cfg::type_id::create("cfg");
      end
      uvm_config_db#(runctl_mgmt_env_cfg)::set(this, "*", "cfg", cfg);

      synclink_agent  = runctl_synclink_agent::type_id::create("synclink_agent", this);
      csr_agent       = runctl_csr_agent::type_id::create("csr_agent", this);
      runctl_monitor_h = runctl_sink_monitor::type_id::create("runctl_monitor_h", this);
      upload_monitor_h = upload_sink_monitor::type_id::create("upload_monitor_h", this);
      reset_monitor_h  = reset_monitor::type_id::create("reset_monitor_h", this);
      sb              = runctl_scoreboard::type_id::create("sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      runctl_monitor_h.ap.connect(sb.runctl_imp);
      upload_monitor_h.ap.connect(sb.upload_imp);
      reset_monitor_h.ap.connect(sb.reset_imp);
    endfunction
  endclass

  class runctl_synclink_cmd_seq extends uvm_sequence #(runctl_synclink_item);
    `uvm_object_utils(runctl_synclink_cmd_seq)

    byte unsigned cmd_byte;
    byte unsigned payload_bytes[$];
    bit [2:0]     error_bytes[$];
    bit           use_raw_symbols;
    logic [8:0]   raw_symbols[$];
    int unsigned  tail_idle_cycles = 1;

    function new(string name = "runctl_synclink_cmd_seq");
      super.new(name);
    endfunction

    task body();
      runctl_synclink_item item;
      item = runctl_synclink_item::type_id::create("item");
      item.cmd_byte         = cmd_byte;
      item.payload_q        = payload_bytes;
      item.error_q          = error_bytes;
      item.use_raw_symbols  = use_raw_symbols;
      item.raw_symbol_q     = raw_symbols;
      item.tail_idle_cycles = tail_idle_cycles;
      start_item(item);
      finish_item(item);
    endtask
  endclass

  class runctl_csr_write_seq extends uvm_sequence #(runctl_csr_item);
    `uvm_object_utils(runctl_csr_write_seq)

    bit [4:0]  address;
    bit [31:0] writedata;

    function new(string name = "runctl_csr_write_seq");
      super.new(name);
    endfunction

    task body();
      runctl_csr_item item;
      item = runctl_csr_item::type_id::create("item");
      item.is_write  = 1'b1;
      item.address   = address;
      item.writedata = writedata;
      start_item(item);
      finish_item(item);
    endtask
  endclass

  class runctl_csr_read_seq extends uvm_sequence #(runctl_csr_item);
    `uvm_object_utils(runctl_csr_read_seq)

    bit [4:0]  address;
    bit [31:0] readdata;

    function new(string name = "runctl_csr_read_seq");
      super.new(name);
    endfunction

    task body();
      runctl_csr_item item;
      item = runctl_csr_item::type_id::create("item");
      item.is_write = 1'b0;
      item.address  = address;
      start_item(item);
      finish_item(item);
      readdata = item.readdata;
    endtask
  endclass

  class runctl_mgmt_host_base_test extends uvm_test;
    `uvm_component_utils(runctl_mgmt_host_base_test)

    runctl_mgmt_env     env;
    runctl_mgmt_env_cfg cfg;
    virtual runctl_if   runctl_ctl_vif;

    function new(string name = "runctl_mgmt_host_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = runctl_mgmt_env_cfg::type_id::create("cfg");
      uvm_config_db#(runctl_mgmt_env_cfg)::set(this, "env", "cfg", cfg);
      if (!uvm_config_db#(virtual runctl_if)::get(this, "", "runctl_ctl_vif", runctl_ctl_vif)) begin
        `uvm_fatal(get_type_name(), "Missing runctl_if control handle")
      end
      env = runctl_mgmt_env::type_id::create("env", this);
    endfunction

    task automatic csr_read_once(logic [4:0] address, output logic [31:0] readdata);
      runctl_csr_read_seq csr_read_seq;
      csr_read_seq = runctl_csr_read_seq::type_id::create($sformatf("csr_read_%0d", address));
      csr_read_seq.address = address;
      csr_read_seq.start(env.csr_agent.seqr);
      readdata = csr_read_seq.readdata;
    endtask

    task automatic wait_for_csr_mask(logic [4:0] address,
                                     logic [31:0] mask,
                                     logic [31:0] expected,
                                     int unsigned timeout_cycles,
                                     string label);
      logic [31:0] readdata;
      repeat (timeout_cycles) begin
        csr_read_once(address, readdata);
        if ((readdata & mask) === expected)
          return;
        @(posedge env.csr_agent.driver.vif.clk);
      end

      csr_read_once(address, readdata);
      `uvm_fatal(get_type_name(),
                 $sformatf("%s: CSR[0x%02h] mask=0x%08h expected=0x%08h got=0x%08h",
                           label, address, mask, expected, readdata))
    endtask

    task automatic dump_local_cmd_debug(string label);
      uvm_hdl_data_t req_mm, ack_mm_sync, busy_mm;
      uvm_hdl_data_t req_lvds_sync, req_lvds_seen, ack_lvds;
      uvm_hdl_data_t pending_lvds, consume_lvds, recv_state_dbg, host_state_dbg;
      string         msg;

      if (!uvm_hdl_read("tb_top.dut.dut.local_cmd_req_mm", req_mm)) begin
        `uvm_warning(get_type_name(), {label, ": failed to read local_cmd_req_mm"})
        return;
      end

      void'(uvm_hdl_read("tb_top.dut.dut.local_cmd_ack_mm_sync", ack_mm_sync));
      void'(uvm_hdl_read("tb_top.dut.dut.local_cmd_busy_mm", busy_mm));
      void'(uvm_hdl_read("tb_top.dut.dut.local_cmd_req_lvds_sync", req_lvds_sync));
      void'(uvm_hdl_read("tb_top.dut.dut.local_cmd_req_lvds_seen", req_lvds_seen));
      void'(uvm_hdl_read("tb_top.dut.dut.local_cmd_ack_lvds", ack_lvds));
      void'(uvm_hdl_read("tb_top.dut.dut.local_cmd_pending_lvds", pending_lvds));
      void'(uvm_hdl_read("tb_top.dut.dut.local_cmd_consume_lvds", consume_lvds));
      void'(uvm_hdl_read("tb_top.dut.dut.recv_state", recv_state_dbg));
      void'(uvm_hdl_read("tb_top.dut.dut.host_state", host_state_dbg));

      msg = $sformatf(
          "%s: req_mm=%0h ack_mm_sync=%0h busy_mm=%0h req_lvds_sync=%0h req_lvds_seen=%0h ack_lvds=%0h pending_lvds=%0h consume_lvds=%0h recv_state=0x%02h host_state=0x%02h",
          label, req_mm[0], ack_mm_sync[1:0], busy_mm[0], req_lvds_sync[1:0],
          req_lvds_seen[0], ack_lvds[0], pending_lvds[0], consume_lvds[0],
          recv_state_dbg[7:0], host_state_dbg[7:0]);
      `uvm_info(get_type_name(), msg, UVM_NONE)
    endtask

    task automatic wait_for_runctl(logic [8:0] expected);
      runctl_runctl_obs obs;
      int unsigned      observed_count;
      string            observed_values;
      repeat (cfg.obs_timeout_cycles) begin
        while (env.sb.runctl_q.size() > 0) begin
          obs = env.sb.runctl_q.pop_front();
          if (obs.data === expected)
            return;
          observed_count++;
          if (observed_count <= 8) begin
            if (observed_values.len() != 0)
              observed_values = {observed_values, ", "};
            observed_values = {observed_values, $sformatf("0x%03h", obs.data)};
          end
        end
        @(posedge env.runctl_monitor_h.vif.clk);
      end

      `uvm_fatal(get_type_name(),
                 $sformatf("Timed out waiting for runctl=0x%03h; observed_count=%0d observed={%s}",
                           expected, observed_count,
                           (observed_values.len() != 0) ? observed_values : "none"))
    endtask

    task automatic wait_for_upload(logic [7:0] expected_symbol, logic [23:0] expected_payload);
      runctl_upload_obs obs;
      repeat (cfg.obs_timeout_cycles) begin
        while (env.sb.upload_q.size() > 0) begin
          obs = env.sb.upload_q.pop_front();
          if (obs.data[7:0] === expected_symbol) begin
            if (obs.data[31:8] !== expected_payload) begin
              `uvm_fatal(get_type_name(),
                         $sformatf("Upload payload mismatch exp=0x%06h got=0x%06h",
                                   expected_payload, obs.data[31:8]))
            end
            return;
          end
        end
        @(posedge env.upload_monitor_h.vif.clk);
      end

      `uvm_fatal(get_type_name(),
                 $sformatf("Timed out waiting for upload symbol=0x%02h",
                           expected_symbol))
    endtask

    task automatic wait_for_last_cmd(logic [7:0] expected_cmd);
      runctl_csr_read_seq csr_read_seq;

      repeat (cfg.obs_timeout_cycles) begin
        csr_read_seq = runctl_csr_read_seq::type_id::create("last_cmd_poll");
        csr_read_seq.address = CSR_LAST_CMD;
        csr_read_seq.start(env.csr_agent.seqr);
        if (csr_read_seq.readdata[7:0] === expected_cmd)
          return;
        @(posedge env.csr_agent.driver.vif.clk);
      end

      `uvm_fatal(get_type_name(),
                 $sformatf("Timed out waiting for LAST_CMD=0x%02h",
                           expected_cmd))
    endtask

    task automatic wait_for_run_number(logic [31:0] expected_run_number);
      runctl_csr_read_seq csr_read_seq;

      repeat (cfg.obs_timeout_cycles) begin
        csr_read_seq = runctl_csr_read_seq::type_id::create("run_number_poll");
        csr_read_seq.address = CSR_RUN_NUMBER;
        csr_read_seq.start(env.csr_agent.seqr);
        if (csr_read_seq.readdata === expected_run_number)
          return;
        @(posedge env.csr_agent.driver.vif.clk);
      end

      `uvm_fatal(get_type_name(),
                 $sformatf("Timed out waiting for RUN_NUMBER=0x%08h",
                           expected_run_number))
    endtask

    task automatic wait_for_reset_state(bit exp_dp, bit exp_ct, bit exp_ext);
      repeat (cfg.obs_timeout_cycles) begin
        @(posedge env.reset_monitor_h.vif.clk);
        if (env.reset_monitor_h.vif.dp_hard_reset  === exp_dp &&
            env.reset_monitor_h.vif.ct_hard_reset  === exp_ct &&
            env.reset_monitor_h.vif.ext_hard_reset === exp_ext) begin
          return;
        end
      end

      `uvm_fatal(get_type_name(),
                 $sformatf("Timed out waiting for reset state dp=%0d ct=%0d ext=%0d",
                           exp_dp, exp_ct, exp_ext))
    endtask

    task automatic wait_for_fpga_address(logic [15:0] expected_fpga_address);
      runctl_csr_read_seq csr_read_seq;

      repeat (cfg.obs_timeout_cycles) begin
        csr_read_seq = runctl_csr_read_seq::type_id::create("fpga_address_poll");
        csr_read_seq.address = CSR_FPGA_ADDRESS;
        csr_read_seq.start(env.csr_agent.seqr);
        if (csr_read_seq.readdata[31] === 1'b1 &&
            csr_read_seq.readdata[15:0] === expected_fpga_address)
          return;
        @(posedge env.csr_agent.driver.vif.clk);
      end

      `uvm_fatal(get_type_name(),
                 $sformatf("Timed out waiting for FPGA_ADDRESS=0x%04h",
                           expected_fpga_address))
    endtask

    task automatic expect_no_new_runctl(int unsigned quiet_cycles,
                                        string msg = "unexpected runctl activity");
      int unsigned start_count;
      start_count = env.sb.runctl_count;
      repeat (quiet_cycles) @(posedge env.runctl_monitor_h.vif.clk);
      if (env.sb.runctl_count != start_count) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("%s: runctl_count changed from %0d to %0d",
                             msg, start_count, env.sb.runctl_count))
      end
    endtask

    task automatic expect_no_new_upload(int unsigned quiet_cycles,
                                        string msg = "unexpected upload activity");
      int unsigned start_count;
      start_count = env.sb.upload_count;
      repeat (quiet_cycles) @(posedge env.upload_monitor_h.vif.clk);
      if (env.sb.upload_count != start_count) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("%s: upload_count changed from %0d to %0d",
                             msg, start_count, env.sb.upload_count))
      end
    endtask

    task automatic clear_observations();
      env.sb.runctl_q.delete();
      env.sb.upload_q.delete();
      env.sb.reset_q.delete();
      env.sb.runctl_count = 0;
      env.sb.upload_count = 0;
      env.sb.reset_count  = 0;
    endtask

    task automatic wait_for_startup_settle();
      // Let both reset domains come cleanly out of reset before driving traffic.
      repeat (24) @(posedge env.runctl_monitor_h.vif.clk);
      repeat (8)  @(posedge env.csr_agent.driver.vif.clk);
    endtask
  endclass

  class runctl_mgmt_host_smoke_test extends runctl_mgmt_host_base_test;
    `uvm_component_utils(runctl_mgmt_host_smoke_test)

    function new(string name = "runctl_mgmt_host_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      runctl_csr_read_seq     csr_read_seq;
      runctl_csr_write_seq    csr_write_seq;

      phase.raise_objection(this);

      wait_for_startup_settle();

      csr_read_seq = runctl_csr_read_seq::type_id::create("uid_read");
      csr_read_seq.address = CSR_UID;
      csr_read_seq.start(env.csr_agent.seqr);
      if (csr_read_seq.readdata !== IP_UID_DEFAULT) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("UID mismatch exp=0x%08h got=0x%08h",
                             IP_UID_DEFAULT, csr_read_seq.readdata))
      end

      csr_read_seq = runctl_csr_read_seq::type_id::create("ack_read");
      csr_read_seq.address = CSR_ACK_SYMBOLS;
      csr_read_seq.start(env.csr_agent.seqr);
      if (csr_read_seq.readdata[7:0] !== RUN_START_ACK_SYMBOL_CONST ||
          csr_read_seq.readdata[15:8] !== RUN_END_ACK_SYMBOL_CONST) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("ACK_SYMBOLS mismatch got=0x%08h",
                             csr_read_seq.readdata))
      end

      csr_write_seq = runctl_csr_write_seq::type_id::create("local_run_prepare");
      csr_write_seq.address   = CSR_LOCAL_CMD;
      csr_write_seq.writedata = 32'h1234_5610;
      csr_write_seq.start(env.csr_agent.seqr);
      wait_for_last_cmd(CMD_RUN_PREPARE);
      wait_for_run_number(32'h0012_3456);

      csr_write_seq = runctl_csr_write_seq::type_id::create("assert_reset");
      csr_write_seq.address   = CSR_LOCAL_CMD;
      csr_write_seq.writedata = 32'h0000_0330;
      csr_write_seq.start(env.csr_agent.seqr);
      wait_for_last_cmd(CMD_RESET);
      wait_for_reset_state(1'b1, 1'b1, 1'b1);

      csr_write_seq = runctl_csr_write_seq::type_id::create("release_reset");
      csr_write_seq.address   = CSR_LOCAL_CMD;
      csr_write_seq.writedata = 32'h0000_0331;
      csr_write_seq.start(env.csr_agent.seqr);
      wait_for_last_cmd(CMD_STOP_RESET);
      wait_for_reset_state(1'b0, 1'b0, 1'b0);

      csr_read_seq = runctl_csr_read_seq::type_id::create("last_cmd_read");
      csr_read_seq.address = CSR_LAST_CMD;
      csr_read_seq.start(env.csr_agent.seqr);
      if (csr_read_seq.readdata[7:0] !== CMD_STOP_RESET) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("LAST_CMD mismatch got=0x%08h",
                             csr_read_seq.readdata))
      end
      if (env.sb.runctl_count !== 1 || env.sb.upload_count !== 1) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("Unexpected smoke traffic counts runctl=%0d upload=%0d",
                             env.sb.runctl_count, env.sb.upload_count))
      end

      `uvm_info(get_type_name(), "*** TEST PASSED ***", UVM_NONE)
      phase.drop_objection(this);
    endtask
  endclass

  class runctl_mgmt_host_ext_reset_auto_release_test extends runctl_mgmt_host_base_test;
    `uvm_component_utils(runctl_mgmt_host_ext_reset_auto_release_test)

    function new(string name = "runctl_mgmt_host_ext_reset_auto_release_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      runctl_csr_write_seq csr_write_seq;

      phase.raise_objection(this);

      wait_for_startup_settle();

      csr_write_seq = runctl_csr_write_seq::type_id::create("assert_reset");
      csr_write_seq.address   = CSR_LOCAL_CMD;
      csr_write_seq.writedata = 32'h0000_0330;
      csr_write_seq.start(env.csr_agent.seqr);
      wait_for_last_cmd(CMD_RESET);
      wait_for_reset_state(1'b1, 1'b1, 1'b1);
      wait_for_reset_state(1'b1, 1'b1, 1'b0);

      repeat (16) @(posedge env.reset_monitor_h.vif.clk);
      if (env.reset_monitor_h.vif.dp_hard_reset  !== 1'b1 ||
          env.reset_monitor_h.vif.ct_hard_reset  !== 1'b1 ||
          env.reset_monitor_h.vif.ext_hard_reset !== 1'b0) begin
        `uvm_fatal(get_type_name(),
                   "Local hard resets did not remain held after ext_hard_reset auto-release")
      end

      csr_write_seq = runctl_csr_write_seq::type_id::create("release_reset");
      csr_write_seq.address   = CSR_LOCAL_CMD;
      csr_write_seq.writedata = 32'h0000_0331;
      csr_write_seq.start(env.csr_agent.seqr);
      wait_for_last_cmd(CMD_STOP_RESET);
      wait_for_reset_state(1'b0, 1'b0, 1'b0);

      `uvm_info(get_type_name(), "*** TEST PASSED ***", UVM_NONE)
      phase.drop_objection(this);
    endtask
  endclass

  class runctl_mgmt_host_synclink_cmd_matrix_test extends runctl_mgmt_host_base_test;
    `uvm_component_utils(runctl_mgmt_host_synclink_cmd_matrix_test)

    function new(string name = "runctl_mgmt_host_synclink_cmd_matrix_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task automatic send_synclink_cmd(string seq_name,
                                     byte unsigned cmd_byte,
                                     byte unsigned payload_bytes[$]);
      runctl_synclink_cmd_seq synclink_seq;
      synclink_seq = runctl_synclink_cmd_seq::type_id::create(seq_name);
      synclink_seq.cmd_byte = cmd_byte;
      synclink_seq.payload_bytes = payload_bytes;
      synclink_seq.tail_idle_cycles = 2;
      synclink_seq.start(env.synclink_agent.seqr);
    endtask

    task automatic send_synclink_byte(string seq_name, byte unsigned cmd_byte);
      byte unsigned payload_bytes[$];
      send_synclink_cmd(seq_name, cmd_byte, payload_bytes);
    endtask

    task run_phase(uvm_phase phase);
      runctl_csr_read_seq csr_read_seq;
      byte unsigned       payload_bytes[$];

      phase.raise_objection(this);

      wait_for_startup_settle();
      clear_observations();

      payload_bytes = {8'h78, 8'h56, 8'h34, 8'h12};
      send_synclink_cmd("synclink_run_prepare", CMD_RUN_PREPARE, payload_bytes);
      wait_for_last_cmd(CMD_RUN_PREPARE);
      wait_for_run_number(32'h1234_5678);
      wait_for_runctl(RUNCTL_RUN_PREPARE);
      wait_for_upload(RUN_START_ACK_SYMBOL_CONST, 24'h345678);

      send_synclink_byte("synclink_run_sync", CMD_RUN_SYNC);
      wait_for_last_cmd(CMD_RUN_SYNC);
      wait_for_runctl(RUNCTL_RUN_SYNC);
      expect_no_new_upload(cfg.obs_timeout_cycles, "RUN_SYNC must not upload");

      send_synclink_byte("synclink_start_run", CMD_START_RUN);
      wait_for_last_cmd(CMD_START_RUN);
      wait_for_runctl(RUNCTL_START_RUN);
      expect_no_new_upload(cfg.obs_timeout_cycles, "START_RUN must not upload");

      send_synclink_byte("synclink_end_run", CMD_END_RUN);
      wait_for_last_cmd(CMD_END_RUN);
      wait_for_runctl(RUNCTL_END_RUN);
      wait_for_upload(RUN_END_ACK_SYMBOL_CONST, 24'h000000);

      send_synclink_byte("synclink_abort_run", CMD_ABORT_RUN);
      wait_for_last_cmd(CMD_ABORT_RUN);
      wait_for_runctl(RUNCTL_IDLE);
      expect_no_new_upload(cfg.obs_timeout_cycles, "ABORT_RUN must not upload");

      send_synclink_byte("synclink_start_link_test", CMD_START_LINK_TEST);
      wait_for_last_cmd(CMD_START_LINK_TEST);
      wait_for_runctl(RUNCTL_LINK_TEST);
      expect_no_new_upload(cfg.obs_timeout_cycles, "START_LINK_TEST must not upload");

      send_synclink_byte("synclink_stop_link_test", CMD_STOP_LINK_TEST);
      wait_for_last_cmd(CMD_STOP_LINK_TEST);
      wait_for_runctl(RUNCTL_IDLE);
      expect_no_new_upload(cfg.obs_timeout_cycles, "STOP_LINK_TEST must not upload");

      send_synclink_byte("synclink_start_sync_test", CMD_START_SYNC_TEST);
      wait_for_last_cmd(CMD_START_SYNC_TEST);
      wait_for_runctl(RUNCTL_SYNC_TEST);
      expect_no_new_upload(cfg.obs_timeout_cycles, "START_SYNC_TEST must not upload");

      send_synclink_byte("synclink_test_sync", CMD_TEST_SYNC);
      wait_for_last_cmd(CMD_TEST_SYNC);
      wait_for_runctl(RUNCTL_SYNC_TEST);
      expect_no_new_upload(cfg.obs_timeout_cycles, "TEST_SYNC must not upload");

      send_synclink_byte("synclink_stop_sync_test", CMD_STOP_SYNC_TEST);
      wait_for_last_cmd(CMD_STOP_SYNC_TEST);
      wait_for_runctl(RUNCTL_IDLE);
      expect_no_new_upload(cfg.obs_timeout_cycles, "STOP_SYNC_TEST must not upload");

      send_synclink_byte("synclink_reset", CMD_RESET);
      wait_for_last_cmd(CMD_RESET);
      wait_for_reset_state(1'b1, 1'b1, 1'b1);
      expect_no_new_runctl(cfg.obs_timeout_cycles, "RESET must not fan out");
      expect_no_new_upload(cfg.obs_timeout_cycles, "RESET must not upload");

      send_synclink_byte("synclink_stop_reset", CMD_STOP_RESET);
      wait_for_last_cmd(CMD_STOP_RESET);
      wait_for_reset_state(1'b0, 1'b0, 1'b0);
      expect_no_new_runctl(cfg.obs_timeout_cycles, "STOP_RESET must not fan out");
      expect_no_new_upload(cfg.obs_timeout_cycles, "STOP_RESET must not upload");

      send_synclink_byte("synclink_enable", CMD_ENABLE);
      wait_for_last_cmd(CMD_ENABLE);
      wait_for_runctl(RUNCTL_IDLE);
      expect_no_new_upload(cfg.obs_timeout_cycles, "ENABLE must not upload");

      send_synclink_byte("synclink_disable", CMD_DISABLE);
      wait_for_last_cmd(CMD_DISABLE);
      wait_for_runctl(RUNCTL_OUT_OF_DAQ);
      expect_no_new_upload(cfg.obs_timeout_cycles, "DISABLE must not upload");

      payload_bytes = {8'hBE, 8'hEF};
      send_synclink_cmd("synclink_address", CMD_ADDRESS, payload_bytes);
      wait_for_last_cmd(CMD_ADDRESS);
      wait_for_fpga_address(16'hBEEF);
      expect_no_new_runctl(cfg.obs_timeout_cycles, "ADDRESS must not fan out");
      expect_no_new_upload(cfg.obs_timeout_cycles, "ADDRESS must not upload");

      csr_read_seq = runctl_csr_read_seq::type_id::create("final_fpga_addr_read");
      csr_read_seq.address = CSR_FPGA_ADDRESS;
      csr_read_seq.start(env.csr_agent.seqr);
      if (csr_read_seq.readdata !== 32'h8000_BEEF) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("FPGA_ADDRESS mismatch got=0x%08h",
                             csr_read_seq.readdata))
      end
      if (env.sb.runctl_count !== 12 || env.sb.upload_count !== 2) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("Unexpected synclink matrix counts runctl=%0d upload=%0d",
                             env.sb.runctl_count, env.sb.upload_count))
      end

      `uvm_info(get_type_name(), "*** TEST PASSED ***", UVM_NONE)
      phase.drop_objection(this);
    endtask
  endclass

  class runctl_mgmt_host_swb_run_number_endian_test extends runctl_mgmt_host_base_test;
    `uvm_component_utils(runctl_mgmt_host_swb_run_number_endian_test)

    function new(string name = "runctl_mgmt_host_swb_run_number_endian_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      runctl_synclink_cmd_seq synclink_seq;
      byte unsigned           payload_bytes[$];

      phase.raise_objection(this);

      wait_for_startup_settle();
      clear_observations();

      payload_bytes = {8'h2A, 8'h00, 8'h00, 8'h00};
      synclink_seq = runctl_synclink_cmd_seq::type_id::create("swb_run_prepare_42");
      synclink_seq.cmd_byte = CMD_RUN_PREPARE;
      synclink_seq.payload_bytes = payload_bytes;
      synclink_seq.tail_idle_cycles = 2;
      synclink_seq.start(env.synclink_agent.seqr);

      wait_for_last_cmd(CMD_RUN_PREPARE);
      wait_for_run_number(32'h0000_002A);
      wait_for_runctl(RUNCTL_RUN_PREPARE);
      wait_for_upload(RUN_START_ACK_SYMBOL_CONST, 24'h00002A);

      if (env.sb.runctl_count !== 1 || env.sb.upload_count !== 1) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("Unexpected SWB endian counts runctl=%0d upload=%0d",
                             env.sb.runctl_count, env.sb.upload_count))
      end

      `uvm_info(get_type_name(), "*** TEST PASSED ***", UVM_NONE)
      phase.drop_objection(this);
    endtask
  endclass

  class runctl_mgmt_host_local_cmd_backpressure_test extends runctl_mgmt_host_base_test;
    `uvm_component_utils(runctl_mgmt_host_local_cmd_backpressure_test)

    function new(string name = "runctl_mgmt_host_local_cmd_backpressure_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      runctl_csr_write_seq csr_write_seq;

      phase.raise_objection(this);

      wait_for_startup_settle();
      clear_observations();

      @(posedge runctl_ctl_vif.clk);

      csr_write_seq = runctl_csr_write_seq::type_id::create("local_reset_bypass_bp");
      csr_write_seq.address   = CSR_LOCAL_CMD;
      csr_write_seq.writedata = 32'h0000_0330;
      csr_write_seq.start(env.csr_agent.seqr);

      wait_for_last_cmd(CMD_RESET);
      wait_for_reset_state(1'b1, 1'b1, 1'b1);
      expect_no_new_runctl(cfg.obs_timeout_cycles,
                           "RESET fanned out on readyless runctl");
      wait_for_csr_mask(CSR_STATUS, 32'h40FF_FF33, 32'h0000_0033, 64,
                        "RESET did not retire on readyless runctl");

      csr_write_seq = runctl_csr_write_seq::type_id::create("local_stop_reset_bypass_bp");
      csr_write_seq.address   = CSR_LOCAL_CMD;
      csr_write_seq.writedata = 32'h0000_0331;
      csr_write_seq.start(env.csr_agent.seqr);

      wait_for_last_cmd(CMD_STOP_RESET);
      wait_for_reset_state(1'b0, 1'b0, 1'b0);
      expect_no_new_runctl(cfg.obs_timeout_cycles,
                           "STOP_RESET fanned out on readyless runctl");
      wait_for_csr_mask(CSR_STATUS, 32'h40FF_FF03, 32'h0000_0003, 64,
                        "STOP_RESET did not retire on readyless runctl");

      csr_write_seq = runctl_csr_write_seq::type_id::create("local_start_run_bp");
      csr_write_seq.address   = CSR_LOCAL_CMD;
      csr_write_seq.writedata = 32'h0000_0012;
      csr_write_seq.start(env.csr_agent.seqr);

      wait_for_last_cmd(CMD_START_RUN);
      wait_for_runctl(RUNCTL_START_RUN);
      wait_for_csr_mask(CSR_STATUS, 32'h40FF_FF03, 32'h0000_0003, 64,
                        "status did not return to idle after readyless runctl broadcast");

      `uvm_info(get_type_name(), "*** TEST PASSED ***", UVM_NONE)
      phase.drop_objection(this);
    endtask
  endclass

  class runctl_mgmt_host_synclink_idle_guard_test extends runctl_mgmt_host_base_test;
    `uvm_component_utils(runctl_mgmt_host_synclink_idle_guard_test)

    function new(string name = "runctl_mgmt_host_synclink_idle_guard_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task automatic send_synclink_raw(string seq_name,
                                     logic [8:0] raw_symbols[$],
                                     bit [2:0] raw_errors[$]);
      runctl_synclink_cmd_seq synclink_seq;
      synclink_seq = runctl_synclink_cmd_seq::type_id::create(seq_name);
      synclink_seq.use_raw_symbols = 1'b1;
      synclink_seq.raw_symbols     = raw_symbols;
      synclink_seq.error_bytes     = raw_errors;
      synclink_seq.tail_idle_cycles = 2;
      synclink_seq.start(env.synclink_agent.seqr);
    endtask

    task run_phase(uvm_phase phase);
      logic [31:0] status_readdata;
      logic [31:0] last_cmd_readdata;
      logic [8:0]  raw_symbols[$];
      bit [2:0]    raw_errors[$];

      phase.raise_objection(this);

      wait_for_startup_settle();
      clear_observations();

      @(posedge runctl_ctl_vif.clk);

      raw_symbols = {};
      raw_errors  = {};
      raw_symbols.push_back({1'b0, 8'h00});
      raw_errors.push_back(3'b100);
      raw_symbols.push_back({1'b0, CMD_RESET});
      raw_errors.push_back(3'b000);
      send_synclink_raw("startup_false_reset", raw_symbols, raw_errors);

      wait_for_csr_mask(CSR_STATUS, 32'h00FF_FF03, 32'h0000_0003, 16,
                        "pre-comma data byte escaped RECV_IDLE");
      csr_read_once(CSR_LAST_CMD, last_cmd_readdata);
      if (last_cmd_readdata[7:0] !== 8'h00) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("LAST_CMD changed before idle/comma arm: 0x%08h",
                             last_cmd_readdata))
      end
      expect_no_new_runctl(cfg.obs_timeout_cycles,
                           "pre-comma data byte must not emit runctl");

      raw_symbols = {};
      raw_errors  = {};
      raw_symbols.push_back(SYNCLINK_IDLE_COMMA);
      raw_errors.push_back(3'b000);
      raw_symbols.push_back({1'b0, CMD_RESET});
      raw_errors.push_back(3'b000);
      send_synclink_raw("comma_then_reset", raw_symbols, raw_errors);

      wait_for_last_cmd(CMD_RESET);
      wait_for_reset_state(1'b1, 1'b1, 1'b1);
      expect_no_new_runctl(cfg.obs_timeout_cycles,
                           "comma-qualified RESET must not emit runctl");
      expect_no_new_upload(cfg.obs_timeout_cycles, "RESET must not upload");
      wait_for_csr_mask(CSR_STATUS, 32'h00FF_FF33, 32'h0000_0033, 64,
                        "comma-qualified RESET did not retire");

      raw_symbols = {};
      raw_errors  = {};
      raw_symbols.push_back(SYNCLINK_IDLE_COMMA);
      raw_errors.push_back(3'b000);
      raw_symbols.push_back({1'b0, CMD_STOP_RESET});
      raw_errors.push_back(3'b000);
      send_synclink_raw("comma_then_stop_reset", raw_symbols, raw_errors);

      wait_for_last_cmd(CMD_STOP_RESET);
      wait_for_reset_state(1'b0, 1'b0, 1'b0);
      expect_no_new_runctl(cfg.obs_timeout_cycles,
                           "comma-qualified STOP_RESET must not emit runctl");
      expect_no_new_upload(cfg.obs_timeout_cycles, "STOP_RESET must not upload");
      wait_for_csr_mask(CSR_STATUS, 32'h00FF_FF03, 32'h0000_0003, 64,
                        "comma-qualified STOP_RESET did not retire");

      csr_read_once(CSR_STATUS, status_readdata);
      if (env.sb.runctl_count != 0 || env.sb.upload_count != 0) begin
        `uvm_fatal(get_type_name(),
                   $sformatf("Unexpected startup-guard traffic counts runctl=%0d upload=%0d status=0x%08h",
                             env.sb.runctl_count, env.sb.upload_count, status_readdata))
      end

      `uvm_info(get_type_name(), "*** TEST PASSED ***", UVM_NONE)
      phase.drop_objection(this);
    endtask
  endclass
endpackage
