`timescale 1ps/1ps

interface csr_if(input logic clk);
  logic [4:0]  address;
  logic        read;
  logic [31:0] readdata;
  logic        write;
  logic [31:0] writedata;
  logic        waitrequest;

  initial begin
    address   = '0;
    read      = 1'b0;
    write     = 1'b0;
    writedata = '0;
  end

  modport drv (input clk, output address, output read, input readdata, output write, output writedata, input waitrequest);
  modport mon (input clk, input address, input read, input readdata, input write, input writedata, input waitrequest);
endinterface
