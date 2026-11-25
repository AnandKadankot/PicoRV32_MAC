| PIPE | result | checks |
|---:|---|---:|
| 0 | PASS | 20269 |
| 1 | PASS | 20269 |
| 2 | PASS | 20269 |

| mutant (PIPE = 2) | injected bug | testbench result | errors reported |
|---|---|---|---:|
| m01_drop_hi_lane | mac16x2 ignores the upper 16-bit lane | FAIL | 10169 |
| m02_unsigned_lanes | 16-bit lanes multiplied as unsigned | FAIL | 8771 |
| m03_hi_lane_wrong_half | upper lane uses the low half of rs2 | FAIL | 10169 |
| m04_macrst_accumulates | macrst adds to the old accumulator instead of replacing it | FAIL | 20261 |
| m05_macrd_updates_acc | macrd also writes the accumulator | FAIL | 7658 |
| m06_macrd_returns_sum | macrd returns acc + prod instead of acc | FAIL | 5075 |
| m07_decode_ignores_funct3 | decoder ignores funct3 (answers foreign instructions) | FAIL | 2 |
| m08_decode_ignores_funct7 | decoder ignores funct7[6:2] (answers foreign instructions) | FAIL | 2 |
| m09_reissue_while_busy | new operation can start while one is in flight | FAIL | 12663 |
| m10_acc_reset_value | accumulator resets to 1 instead of 0 | FAIL | 4 |

**Mutation detection rate: 10/10 = 100%**
