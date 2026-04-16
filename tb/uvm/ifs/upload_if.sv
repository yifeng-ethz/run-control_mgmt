`timescale 1ps/1ps

interface upload_if(input logic clk);
  logic [35:0] data;
  logic        valid;
  logic        ready;
  logic        startofpacket;
  logic        endofpacket;

  initial begin
    ready = 1'b1;
  end

  modport mon  (input clk, input data, input valid, input ready, input startofpacket, input endofpacket);
  modport sink (input clk, input data, input valid, output ready, input startofpacket, input endofpacket);
endinterface
