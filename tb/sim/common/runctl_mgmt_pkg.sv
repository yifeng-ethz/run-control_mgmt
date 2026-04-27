`timescale 1ps/1ps

package runctl_mgmt_pkg;
  localparam logic [7:0] CMD_RUN_PREPARE = 8'h10;
  localparam logic [7:0] CMD_RUN_SYNC    = 8'h11;
  localparam logic [7:0] CMD_START_RUN   = 8'h12;
  localparam logic [7:0] CMD_END_RUN     = 8'h13;
  localparam logic [7:0] CMD_ABORT_RUN   = 8'h14;
  localparam logic [7:0] CMD_START_LINK_TEST = 8'h20;
  localparam logic [7:0] CMD_STOP_LINK_TEST  = 8'h21;
  localparam logic [7:0] CMD_START_SYNC_TEST = 8'h24;
  localparam logic [7:0] CMD_STOP_SYNC_TEST  = 8'h25;
  localparam logic [7:0] CMD_TEST_SYNC       = 8'h26;
  localparam logic [7:0] CMD_RESET       = 8'h30;
  localparam logic [7:0] CMD_STOP_RESET  = 8'h31;
  localparam logic [7:0] CMD_ENABLE      = 8'h32;
  localparam logic [7:0] CMD_DISABLE     = 8'h33;
  localparam logic [7:0] CMD_ADDRESS     = 8'h40;
  localparam logic [8:0] SYNCLINK_IDLE_COMMA = 9'h1BC;

  localparam logic [8:0] RUNCTL_IDLE        = 9'b000000001;
  localparam logic [8:0] RUNCTL_RUN_PREPARE = 9'b000000010;
  localparam logic [8:0] RUNCTL_RUN_SYNC    = 9'b000000100;
  localparam logic [8:0] RUNCTL_START_RUN   = 9'b000001000;
  localparam logic [8:0] RUNCTL_END_RUN     = 9'b000010000;
  localparam logic [8:0] RUNCTL_LINK_TEST   = 9'b000100000;
  localparam logic [8:0] RUNCTL_SYNC_TEST   = 9'b001000000;
  localparam logic [8:0] RUNCTL_RESET       = 9'b010000000;
  localparam logic [8:0] RUNCTL_OUT_OF_DAQ  = 9'b100000000;

  localparam logic [4:0] CSR_UID          = 5'h00;
  localparam logic [4:0] CSR_META         = 5'h01;
  localparam logic [4:0] CSR_CONTROL      = 5'h02;
  localparam logic [4:0] CSR_STATUS       = 5'h03;
  localparam logic [4:0] CSR_LAST_CMD     = 5'h04;
  localparam logic [4:0] CSR_SCRATCH      = 5'h05;
  localparam logic [4:0] CSR_RUN_NUMBER   = 5'h06;
  localparam logic [4:0] CSR_RESET_MASK   = 5'h07;
  localparam logic [4:0] CSR_FPGA_ADDRESS = 5'h08;
  localparam logic [4:0] CSR_RECV_TS_L    = 5'h09;
  localparam logic [4:0] CSR_RECV_TS_H    = 5'h0A;
  localparam logic [4:0] CSR_EXEC_TS_L    = 5'h0B;
  localparam logic [4:0] CSR_EXEC_TS_H    = 5'h0C;
  localparam logic [4:0] CSR_GTS_L        = 5'h0D;
  localparam logic [4:0] CSR_GTS_H        = 5'h0E;
  localparam logic [4:0] CSR_RX_CMD_COUNT = 5'h0F;
  localparam logic [4:0] CSR_RX_ERR_COUNT = 5'h10;
  localparam logic [4:0] CSR_LOG_STATUS   = 5'h11;
  localparam logic [4:0] CSR_LOG_POP      = 5'h12;
  localparam logic [4:0] CSR_LOCAL_CMD    = 5'h13;
  localparam logic [4:0] CSR_ACK_SYMBOLS  = 5'h14;

  localparam logic [31:0] IP_UID_DEFAULT             = 32'h5243_4D48;
  localparam logic [7:0]  RUN_START_ACK_SYMBOL_CONST = 8'hFE;
  localparam logic [7:0]  RUN_END_ACK_SYMBOL_CONST   = 8'hFD;

  localparam int unsigned MM_CLK_PERIOD_PS   = 6667;
  localparam int unsigned LVDS_CLK_PERIOD_PS = 8000;

  function automatic logic [31:0] runctl_lcg_next(input logic [31:0] state);
    return state * 32'd1664525 + 32'd1013904223;
  endfunction

  function automatic logic [8:0] runctl_decode(input logic [7:0] cmd);
    case (cmd)
      CMD_RUN_PREPARE: runctl_decode = RUNCTL_RUN_PREPARE;
      CMD_RUN_SYNC:    runctl_decode = RUNCTL_RUN_SYNC;
      CMD_START_RUN:   runctl_decode = RUNCTL_START_RUN;
      CMD_END_RUN:     runctl_decode = RUNCTL_END_RUN;
      CMD_START_LINK_TEST: runctl_decode = RUNCTL_LINK_TEST;
      CMD_START_SYNC_TEST: runctl_decode = RUNCTL_SYNC_TEST;
      CMD_TEST_SYNC:       runctl_decode = RUNCTL_SYNC_TEST;
      CMD_RESET:       runctl_decode = RUNCTL_RESET;
      CMD_DISABLE:     runctl_decode = RUNCTL_OUT_OF_DAQ;
      default:         runctl_decode = RUNCTL_IDLE;
    endcase
  endfunction
endpackage
