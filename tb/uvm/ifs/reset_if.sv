`timescale 1ps/1ps

interface reset_if(input logic clk);
  logic dp_hard_reset;
  logic ct_hard_reset;
  logic ext_hard_reset;

  modport mon (input clk, input dp_hard_reset, input ct_hard_reset, input ext_hard_reset);
endinterface
