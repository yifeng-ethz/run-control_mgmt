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

      vif.data  = 9'h100;
      vif.error = '0;
      repeat (item.tail_idle_cycles) @(posedge vif.clk);
    endtask

    task run_phase(uvm_phase phase);
      vif.data  = 9'h100;
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
        if (vif.valid && vif.ready) begin
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
      $cast(clone_obs, t.clone());
      runctl_count++;
      runctl_q.push_back(clone_obs);
      -> runctl_ev;
    endfunction

    function void write_upload(runctl_upload_obs t);
      runctl_upload_obs clone_obs;
      $cast(clone_obs, t.clone());
      upload_count++;
      upload_q.push_back(clone_obs);
      -> upload_ev;
    endfunction

    function void write_reset(runctl_reset_obs t);
      runctl_reset_obs clone_obs;
      $cast(clone_obs, t.clone());
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

    function new(string name = "runctl_mgmt_host_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = runctl_mgmt_env_cfg::type_id::create("cfg");
      uvm_config_db#(runctl_mgmt_env_cfg)::set(this, "env", "cfg", cfg);
      env = runctl_mgmt_env::type_id::create("env", this);
    endfunction

    task automatic wait_for_runctl(logic [8:0] expected);
      runctl_runctl_obs obs;
      fork
        begin
          forever begin
            while (env.sb.runctl_q.size() > 0) begin
              obs = env.sb.runctl_q.pop_front();
              if (obs.data === expected)
                disable fork;
            end
            @env.sb.runctl_ev;
          end
        end
        begin
          repeat (cfg.obs_timeout_cycles) @(posedge env.runctl_monitor_h.vif.clk);
          `uvm_fatal(get_type_name(),
                     $sformatf("Timed out waiting for runctl=0x%03h", expected))
        end
      join_any
      disable fork;
    endtask

    task automatic wait_for_upload(logic [7:0] expected_symbol, logic [23:0] expected_payload);
      runctl_upload_obs obs;
      fork
        begin
          forever begin
            while (env.sb.upload_q.size() > 0) begin
              obs = env.sb.upload_q.pop_front();
              if (obs.data[7:0] === expected_symbol) begin
                if (obs.data[31:8] !== expected_payload) begin
                  `uvm_fatal(get_type_name(),
                             $sformatf("Upload payload mismatch exp=0x%06h got=0x%06h",
                                       expected_payload, obs.data[31:8]))
                end
                disable fork;
              end
            end
            @env.sb.upload_ev;
          end
        end
        begin
          repeat (cfg.obs_timeout_cycles) @(posedge env.upload_monitor_h.vif.clk);
          `uvm_fatal(get_type_name(),
                     $sformatf("Timed out waiting for upload symbol=0x%02h",
                               expected_symbol))
        end
      join_any
      disable fork;
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

      repeat (12) @(posedge env.csr_agent.driver.vif.clk);

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

      `uvm_info(get_type_name(), "*** TEST PASSED ***", UVM_NONE)
      phase.drop_objection(this);
    endtask
  endclass
endpackage
