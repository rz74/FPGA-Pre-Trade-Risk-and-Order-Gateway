# Latency / Throughput Table (Placeholder)

| Stage                  | Cycles | Notes                         |
|------------------------|:------:|-------------------------------|
| Ingress Unpack         |   1    | Field slice                   |
| NBBO/Limit Snapshot    |   1    | Dual-port BRAM read           |
| Size/Notional Check    |   1    | DSP mult if needed            |
| Price Collar Check     |   1    | Compare vs NBBO               |
| Credit/Position Check  |   2    | BRAM read/modify/write        |
| Throttle Bucket        |   1    | Token logic                   |
| DupID CAM              |   1    | Lookup/insert                 |
| STP Booklet            |   1    | Window check                  |
| Decision Arbiter       |   1    | Priority encode               |
| State Update           |   2    | BRAM updates                  |
| OUCH Encoder (stub)    |   1    | Pack fields                   |
| **Total (target)**     | **12–15** | ~ @ 250 MHz (~48–60 ns)     |
