`timescale 1ns/1ps
// Optional: 32x32->64 multiply using DSPs; wire up as needed.
module mul32x32_dsp (
    input  wire clk,
    input  wire rst_n,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        valid_in,
    output wire [63:0] p,
    output wire        valid_out
);
// TODO
assign p = a * b;
assign valid_out = valid_in;
endmodule
