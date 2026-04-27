`timescale 1ps/1ps

interface synclink_if(input logic clk);
  import runctl_mgmt_pkg::*;

  logic [8:0] data;
  logic [2:0] error;

  initial begin
    data  = SYNCLINK_IDLE_COMMA;
    error = '0;
  end

  modport drv (input clk, output data, output error);
  modport mon (input clk, input data, input error);
endinterface
