# FPGA Pre-Trade Risk & Order Gateway

This is an FPGA-based pre-trade risk gateway to sit between a CPU algo and an exchange.

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


## Design Spec

This module sits between the CPU algo and the exchange, enforcing deterministic pre-trade risk checks with ~tens-of-nanoseconds latency.

```
Exchange Feed → ITCH Parser (done) → CPU Algo → FPGA Risk Gateway → Exchange
```

---

## 1. Scope & Assumptions

- **Latency target:** fixed 12–20 cycles @ 250 MHz (≈48–80 ns) from `order_intent.tvalid` to decision.
- **Throughput:** 1 order/clk (no bubbles) under continuous back-to-back load.
- **NBBO source:** ITCH path feeds symbol-scoped NBBO updates into a small on-FPGA cache.
- **State ownership:** gateway tracks **its own** outstanding orders (those sent via this module) for STP/position/credit; host may correct via config writes.
- **STP policy:** **Cancel New** (drop incoming order) when it would self-trade against our outstanding opposite-side order at price-cross or equal.
- **Pass/Reject:** OUCH output emitted only for **PASS**; **REJECT**s go to a host sideband stream with reason codes.

---

## 2. Top-Level Interfaces

### 2.1 Data Plane (AXI-Stream)

- **Order intents in (one-beat, 256-bit):**
  - `s_axis_order_tdata[255:0]`, `s_axis_order_tvalid`, `s_axis_order_tready`, `s_axis_order_tlast=1`
- **NBBO updates in (one-beat, 128-bit):**
  - `s_axis_nbbo_tdata[127:0]`, `s_axis_nbbo_tvalid`, `s_axis_nbbo_tready`
- **Pass path (normalized order to OUCH encoder, 256-bit):**
  - `m_axis_pass_tdata[255:0]`, `m_axis_pass_tvalid`, `m_axis_pass_tready`
- **Reject path (reason record, 128-bit):**
  - `m_axis_reject_tdata[127:0]`, `m_axis_reject_tvalid`, `m_axis_reject_tready`

### 2.2 Control/Status Plane

- **AXI-Lite (32-bit):** config/limits, kill-switch, counters, commit barriers.
- **Event/telemetry (optional AXIS):** `m_axis_evt_tdata[127:0]` for low-rate stats/alerts.

---

## 3. Message Formats

### 3.1 Order Intent (256b, little-endian fields)

| Bits        | Field                           |
|-------------|---------------------------------|
| 63:0        | `order_id` (opaque, from host)  |
| 79:64       | `account_id` (16b)              |
| 111:80      | `symbol_id` (32b; host maps ticker→id) |
| 112         | `side` (0=buy,1=sell)           |
| 127:113     | `reserved0`                     |
| 159:128     | `qty` (32b shares)              |
| 191:160     | `price` (32b, integer ticks)    |
| 199:192     | `tif` (8b)                      |
| 207:200     | `ord_type` (8b: 0=limit,1=market) |
| 223:208     | `route` (16b)                   |
| 239:224     | `ts_client_lo` (16b, optional)  |
| 255:240     | `reserved1`                     |



### 3.2 NBBO Update (128b)

| Bits   | Field                                  |
|--------|----------------------------------------|
| 31:0   | `symbol_id`                            |
| 63:32  | `best_bid_px` (ticks)                  |
| 95:64  | `best_ask_px` (ticks)                  |
| 111:96 | `bid_size` (16b)                       |
| 127:112| `ask_size` (16b)                       |



### 3.3 Reject Record (128b)

| Bits  | Field                                    |
|-------|------------------------------------------|
| 15:0  | `reason_code`                            |
| 31:16 | `stage_latency_cycles`                   |
| 63:32 | `account_id`                             |
| 95:64 | `symbol_id`                              |
| 127:96| `order_id_hash` (or low 32 of `order_id`) |

### 3.4 Reason Codes (priority order)

```
0x0000 PASS (not emitted on pass)
0x0001 KILL_SWITCH
0x0002 MAX_QTY
0x0003 MAX_NOTIONAL
0x0004 PRICE_COLLAR
0x0005 CREDIT_LIMIT
0x0006 POSITION_LIMIT
0x0007 THROTTLE
0x0008 DUP_ORDER_ID
0x0009 STP_CANCEL_NEW
0x000A NBBO_STALE
0x00FE SCHEMA_ERR
0x00FF INTERNAL_ERR
```

---

## 4. Memory/State & AXI-Lite Map (high-level)

- **Global CSR (0x0000):**
  - `CTRL`: bit0 `kill`, bit1 `nbbo_en`, bit2 `stp_en`, bit3 `dup_en`
  - `COMMIT_SEQ`: write to advance config epoch atomically
  - `STATS_*`: pass/reject counters, FIFO high-watermarks
- **Account limits (0x1000 …):** indexed by `account_id`
  - `max_order_qty`, `max_order_notional`, `credit_limit`
  - `throttle_rate` (tokens/µs), `throttle_burst`
  - `stp_scope` (per account / per firm), `flags`
- **Symbol limits (0x2000 …):** indexed by `symbol_id`
  - `price_collar_ticks` (or bps), `position_limit_qty`, `nbbo_max_age_cycles`
- **State (hardware-owned, RO or W1C):**
  - `acct_exposure_notional`, `acct_tokens`
  - `symbol_position_qty` (net), `inflight_qty`
- **Tables:**
  - **NBBO cache:** BRAM × `N_SYMBOLS` (bid_px, ask_px, age)
  - **DupID CAM:** depth K (e.g., 4K entries), key=`{account_id, order_id_hash}`, with TTL
  - **STP booklet:** per symbol small set-assoc of our resting orders `{side, price, qty}` with LRU
  - **Throttle state:** per account token bucket registers

**Atomic updates:** host writes multiple fields, then writes `COMMIT_SEQ` to publish a new epoch. Pipeline latches epoch at ingress; lookups use a single consistent snapshot.

---

## 5. Module Breakdown (with cycle budget)

1. **`ingress_unpack` (1–2c):** Latch, basic field checks, compute `notional = qty*price` (start DSP).
2. **`snapshot_mux` (0–1c):** Capture `epoch_id` and route to consistent BRAM ports.
3. **`nbbo_cache` (1c read):** Dual-port BRAM; write from `s_axis_nbbo`, read by pipeline; flag `nbbo_stale`.
4. **`symbol_limits_bram` (1c read):** Pull `price_collar`, `pos_limit`, etc.
5. **`account_limits_bram` (1c read):** Pull `max_qty/notional`, `credit`, `throttle params`, `stp_scope`.
6. **`size_notional_check` (1c):** Compare `qty`, `notional` vs limits.
7. **`price_collar_check` (1c):** If limit order: ensure buy `price ≤ ask + collar`, sell `price ≥ bid − collar`; market orders require NBBO presence (or reject if disabled).
8. **`credit_position_check` (2c):** Check `exposure_notional + notional ≤ credit_limit`; `position + signed(qty) ≤ pos_limit` (signed by side & STP policy).
9. **`throttle_bucket` (1c):** Refill from cycle counter; `tokens ≥ cost?` (cost=1 per order).
10. **`dup_id_cam` (1c):** Parallel compare (hashed segment) or BRAM + small CAM; return hit.
11. **`stp_probe` (2c):** Probe booklet for opposite-side `price_cross_or_equal`; hit ⇒ STP drop.
12. **`decision_arbiter` (1c):** Priority encoder over reason flags (per the list).
13. **`state_update` (2c, only on PASS):** Update exposure, position, tokens (consume), insert DupID, update STP booklet.
14. **`ouch_encoder` (2–4c):** Map normalized order to OUCH Enter-Order frame (or keep stub initially).
15. **`reject_sink` (1c):** Emit reason record.

**Total:** ~16–19 cycles worst-case, **II=1**.

---

## 6. Price-Collar & STP Details

- **Collar modes:** ticks or bps (select via symbol flag). Use NBBO mid or side reference:  
  - Buy: `price ≤ min(ask, mid + collar)`  
  - Sell: `price ≥ max(bid, mid − collar)`
- **NBBO staleness:** reject (`NBBO_STALE`) if `age_cycles > nbbo_max_age_cycles` for symbol.
- **STP booklet:** small N-way set-assoc per symbol (e.g., 4 ways/side, 2 sets by price hash). Detect **self-cross**: incoming buy vs our resting sells where `price ≥ resting_sell_price` (and vice-versa). Policy **Cancel New**.

---

## 7. Throttle & Duplicate-ID

- **Token bucket per account:** `tokens = min(burst, tokens + rate*Δt)`; require `tokens ≥ 1`; on pass, `tokens -= 1`.
- **DupID store:** `(account_id, order_id_low, epoch_tag)` with configurable TTL (cycle window). Optional Bloom prefilter to reduce CAM compares.

---

## 8. OUCH Encoder (Outbound)

Keep a normalized order bus (same as pass `tdata`) and a separate `ouch_encoder` that formats bytes.

- **Phase 1 (quick):** stub → pass normalized order to a sink FIFO (Cocotb verifies fields).
- **Phase 2:** encode OUCH “Enter Order” message into AXIS8 byte stream.

---

## 9. Pipeline Control & Back-Pressure

- **II=1**: input `tready` deasserts only if PASS or REJECT FIFO almost-full.
- **State updates** occur **after** decision; REJECT path makes no state mutation.
- **Epoching:** all table reads are single-cycle BRAM (true dual-port) with epoch-consistent addresses.

---

## 10. Verification Plan (Cocotb + Python Golden Model)

### 10.1 Golden Model (Python)
- Deterministic functional copy of checks with the **same reason priority** and integer math.
- Maintains structures: per-account credit/exposure & token bucket; per-symbol position; NBBO cache with age; DupID set with TTL; STP booklet.
- Helpers to apply AXI-Lite configs and NBBO updates.

### 10.2 Directed Scenarios
1. **Max qty/notional:** at limit, +1 over, multiple symbols.
2. **Price collar edges:** `price == ask`, `price == bid`, bps vs ticks, stale NBBO.
3. **Credit & position:** cumulative passes until limit; then reject; include cancels if implemented.
4. **Throttle:** bursts that exceed rate; recovery after idle.
5. **DupID:** identical `(acct, order_id)` twice within TTL; outside TTL passes.
6. **STP:** seed resting sell @100 → buy @100 rejects; buy @99 passes.
7. **Kill-switch:** toggled mid-stream.
8. **Priority resolution:** craft order violating multiple checks; confirm top-priority reason.

### 10.3 Randomized Workloads
- Poisson order arrivals; Zipf symbols/accounts; random NBBO walks; 100k+ intents.
- Mix limit/market, sides, collars, interleaved cancels/replaces if included.

### 10.4 Back-to-Back Bursts
- Long continuous runs (≥10k cycles) at 1/cycle; verify **no bubbles** and fixed latency.

### 10.5 Stability/Fuzz
- Invalid symbol/account IDs; extreme field values; AXI-Lite updates racing with orders (check epoch atomicity).

### 10.6 Checkers & Metrics
- **Scoreboard:** match PASS/REJECT & reason; match OUCH payload (or normalized pass bus).
- **Latency logging:** cycles from ingress handshake to decision; CSV histogram; min/typ/max must be equal (constant-time).
- **Coverage:** reason codes hit, boundary values, STP hit/miss, throttle under/overflow.
- **Seed reproducibility:** record RNG seeds & config snapshots per run.

### 10.7 Testbench Infrastructure
- AXIS drivers/monitors for orders, NBBO, pass, reject.
- AXI-Lite driver for config writes + `COMMIT_SEQ`.
- CSV emitters for: inputs, NBBO, decisions, reasons, cycle counts.

---

## 11. File/Module Structure (proposed)

```
rtl/
  risk_gateway_top.v
  ingress_unpack.v
  snapshot_mux.v
  nbbo_cache.v
  symbol_limits_bram.v
  account_limits_bram.v
  size_notional_check.v
  price_collar_check.v
  credit_position_check.v
  throttle_bucket.v
  dupid_cam.v
  stp_booklet.v
  decision_arbiter.v
  state_update.v
  ouch_encoder_stub.v   // phase 1
  axi_lite_regs.v
  utils/
    mul32x32_dsp.v
    epoch_ctrl.v
    fifo_axis.v
sim/ (cocotb)
  test_risk_gateway.py
  golden_model.py
  drivers_axis.py
  drivers_axil.py
  scenarios/*.py
docs/
  README.md
  latency_table.md
  diagrams/*.png
```

---

