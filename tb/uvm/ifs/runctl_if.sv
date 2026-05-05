`timescale 1ps/1ps

interface runctl_if(input logic clk);
  logic       valid;
  logic [8:0] data;

  modport mon  (input clk, input valid, input data);
endinterface
