# FPGA Pre-Trade Risk & Order Gateway (Scaffold)

This repository scaffolds an FPGA-based pre-trade risk gateway to sit between a CPU algo and an exchange.

```
Exchange Feed → ITCH Parser (done) → CPU Algo → FPGA Risk Gateway → Exchange
```

## Goals (high level)
- Deterministic decision in ~10–20 cycles @ 250 MHz.
- Core checks: size/notional, price collars vs NBBO, credit/exposure, position limits, throttling, duplicate ID, STP, global kill-switch.
- AXI-Stream/valid-ready dataplane, AXI-Lite control plane.
- BRAM-backed per-symbol/account tables with atomic updates.
- OUCH encoder (stub in phase 1).

## Layout
- `rtl/` — Verilog modules (top + submodules; utils in `rtl/utils/`).
- `sim/` — Cocotb testbench skeleton (drivers, scenarios, golden model).
- `docs/` — README, latency table, diagrams.

## Next Steps
- Flesh out I/O spec, register map, reason codes.
- Implement each check as a 1-cycle stage; verify constant-time path.
- Build cocotb randomized scenarios and CSV logs.

> Scaffold generated on 2025-08-26 14:29:41.
