| config | LUT | FF | DSP | Fmax (MHz) | dyn. power @ target (W) | crit. path end |
|---|---:|---:|---:|---:|---:|---|
| rv32ic | 1250 | 612 | 0 | 149.1 | 0.03 | cpu/mem_rdata_q_reg[24]/D |
| rv32imc_mul | 1535 | 891 | 0 | 144.5 | 0.058 | cpu/mem_rdata_q_reg[12]/CE |
| rv32imc_fastmul | 1388 | 712 | 4 | 146.2 | 0.066 | cpu/mem_rdata_q_reg[28]/CE |
| fastmul_mac_p1 | 1493 | 854 | 9 | 117.8 | 0.075 | g_mac.mac/prod_reg[31]/D |
| fastmul_mac_p0 | 1496 | 800 | 9 | 123.0 | 0.089 | g_mac.mac/prod_reg[29]/D |
| fastmul_mac_p2 | 1488 | 875 | 9 | 149.0 | 0.052 | cpu/decoded_rs1_reg_rep_rep[1]/D |
