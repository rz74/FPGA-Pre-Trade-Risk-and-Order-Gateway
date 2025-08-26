`timescale 1ns/1ps
// Minimal AXI-Stream-like FIFO (valid/ready)
module fifo_axis #(
    parameter WIDTH = 64,
    parameter DEPTH = 16
)(
    input  wire              clk,
    input  wire              rst_n,
    // in
    input  wire              in_valid,
    output wire              in_ready,
    input  wire [WIDTH-1:0]  in_data,
    // out
    output wire              out_valid,
    input  wire              out_ready,
    output wire [WIDTH-1:0]  out_data
);
// TODO: placeholder (no storage)
assign in_ready  = out_ready;
assign out_valid = in_valid;
assign out_data  = in_data;
endmodule
