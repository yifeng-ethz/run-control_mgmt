`timescale 1ps/1ps

interface runctl_if(input logic clk);
  logic       valid;
  logic [8:0] data;
  logic       ready;

  initial begin
    ready = 1'b1;
  end

  modport mon  (input clk, input valid, input data, input ready);
  modport sink (input clk, input valid, input data, output ready);
endinterface
