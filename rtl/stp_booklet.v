`timescale 1ns/1ps
// Check #7: Self-Trade Prevention (simple same-account/symbol/side window)
module stp_booklet (
    input  wire clk,
    input  wire rst_n
    // TODO: track recent resting intents per account/symbol/side; flag if STP rule applies
);
// TODO
endmodule
