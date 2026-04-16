`timescale 1ps/1ps

interface synclink_if(input logic clk);
  logic [8:0] data;
  logic [2:0] error;

  initial begin
    data  = 9'h100;
    error = '0;
  end

  modport drv (input clk, output data, output error);
  modport mon (input clk, input data, input error);
endinterface
