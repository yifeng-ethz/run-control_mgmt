`timescale 1ps/1ps

module tb_top;
  import uvm_pkg::*;
  import runctl_mgmt_pkg::*;
  import runctl_mgmt_env_pkg::*;
  `include "uvm_macros.svh"

  logic mm_clk        = 1'b0;
  logic mm_reset      = 1'b1;
  logic lvdspll_clk   = 1'b0;
  logic lvdspll_reset = 1'b1;

  always #(MM_CLK_PERIOD_PS/2)   mm_clk      = ~mm_clk;
  always #(LVDS_CLK_PERIOD_PS/2) lvdspll_clk = ~lvdspll_clk;

  initial begin
    mm_reset      = 1'b1;
    lvdspll_reset = 1'b1;
    repeat (10) @(posedge lvdspll_clk);
    lvdspll_reset = 1'b0;
    repeat (2) @(posedge mm_clk);
    mm_reset      = 1'b0;
  end

  synclink_if synclink_vif(lvdspll_clk);
  runctl_if   runctl_vif(lvdspll_clk);
  upload_if   upload_vif(lvdspll_clk);
  csr_if      csr_vif(mm_clk);
  reset_if    reset_vif(lvdspll_clk);

  initial begin
    upload_vif.ready = 1'b1;
  end

  runctl_mgmt_host_dut_wrapper #(
    .EXT_HARD_RESET_PULSE_CYCLES(16'd32)
  ) dut (
    .asi_synclink_data       (synclink_vif.data),
    .asi_synclink_error      (synclink_vif.error),
    .aso_upload_data         (upload_vif.data),
    .aso_upload_valid        (upload_vif.valid),
    .aso_upload_ready        (upload_vif.ready),
    .aso_upload_startofpacket(upload_vif.startofpacket),
    .aso_upload_endofpacket  (upload_vif.endofpacket),
    .aso_runctl_valid        (runctl_vif.valid),
    .aso_runctl_data         (runctl_vif.data),
    .avs_csr_address         (csr_vif.address),
    .avs_csr_read            (csr_vif.read),
    .avs_csr_readdata        (csr_vif.readdata),
    .avs_csr_write           (csr_vif.write),
    .avs_csr_writedata       (csr_vif.writedata),
    .avs_csr_waitrequest     (csr_vif.waitrequest),
    .dp_hard_reset           (reset_vif.dp_hard_reset),
    .ct_hard_reset           (reset_vif.ct_hard_reset),
    .ext_hard_reset          (reset_vif.ext_hard_reset),
    .mm_clk                  (mm_clk),
    .mm_reset                (mm_reset),
    .lvdspll_clk             (lvdspll_clk),
    .lvdspll_reset           (lvdspll_reset)
  );

  initial begin
    uvm_config_db#(virtual synclink_if.drv)::set(
      null, "uvm_test_top.env.synclink_agent.driver", "vif", synclink_vif);
    uvm_config_db#(virtual csr_if.drv)::set(
      null, "uvm_test_top.env.csr_agent.driver", "vif", csr_vif);
    uvm_config_db#(virtual runctl_if.mon)::set(
      null, "uvm_test_top.env.runctl_monitor_h", "vif", runctl_vif);
    uvm_config_db#(virtual runctl_if)::set(
      null, "uvm_test_top", "runctl_ctl_vif", runctl_vif);
    uvm_config_db#(virtual upload_if.mon)::set(
      null, "uvm_test_top.env.upload_monitor_h", "vif", upload_vif);
    uvm_config_db#(virtual reset_if.mon)::set(
      null, "uvm_test_top.env.reset_monitor_h", "vif", reset_vif);
    run_test();
  end

  initial begin
    #(2_000_000ns);
    `uvm_fatal("TB_TOP", "Global timeout reached")
  end
endmodule
