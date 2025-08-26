`timescale 1ns/1ps
// FPGA Pre-Trade Risk and Order Gateway — Top
// Skeleton only. Fill in ports and logic as you implement blocks.
// Target: ~10–20 cycles @ 250 MHz for constant-time decisions.
module risk_gateway_top (
    input  wire clk,
    input  wire rst_n
    // TODO: AXI-Stream order intents in
    // TODO: NBBO snapshot/cache in
    // TODO: OUCH/AXI-Stream out to exchange
    // TODO: AXI-Lite control/status
);
    // TODO: instantiate ingress_unpack, nbbo_cache, checks, arbiter, updates, ouch_encoder_stub
endmodule
