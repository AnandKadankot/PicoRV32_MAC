# Full-system implementation (fpga_top, xc7z020clg400-1, PYNQ-Z2 pinout)

System: PicoRV32 RV32IMC + DSP fast multiplier + MAC coprocessor (PIPE=2), 128 KiB block RAM
initialised with `bench_rv32imc_mac.hex`, UART TX (115200 8N1), MMCM 125 MHz -> 125 MHz core clock.
Flow: in-context synthesis, place and route with timing-driven directives (`scripts/vivado_bitstream.tcl ... 125 explore`),
`write_bitstream` completed. Vivado 2025.2.

| metric | value |
|---|---|
| core clock | 125 MHz (8.0 ns) |
| setup WNS / hold WHS | +0.032 ns / +0.036 ns (all constraints met) |
| critical path | block RAM output -> PicoRV32 `mem_rdata_q` |
| Slice LUTs | 1,705 (3.2%) |
| Slice registers | 959 (0.9%) |
| Block RAM tiles | 32 (22.9%) |
| DSP48E1 | 9 (4.1%) (4 fast multiplier + 5 MAC) |
| MMCM / BUFG / IOB | 1 / 1 / 7 |
| total on-chip power (Vivado estimate, vectorless) | 0.243 W (0.134 W dynamic + 0.110 W static) |
| DRC | no errors; DSP-pipelining advisories only (DPOP-1/2) |
| routing | 2,797 / 2,797 nets fully routed, 0 routing errors |
| congestion | no placer congestion window above level 5; router effective congestion level 0–1 (on a 0–8 scale; ≥ 5 is considered congested) |
| clock network | 1 MMCM, 1 BUFG, core clock spans 4 clock regions |
| critical path | BRAM `CLKBWRCLK` → `mem_rdata_q_reg[28]/D`: 4 logic levels, data path 7.650 ns |
| clock skew on critical path | −0.330 ns (destination clock 6.209 ns, source clock 6.955 ns, pessimism removal +0.416 ns); worst setup-path skew −0.332 ns |
| bitstream | generated (`build/bit125/fpga_top.bit`, not committed) |

Pre-bitstream check: `sim/tb_fpga_top.v` simulates the same top level (MMCM, reset, block RAM,
UART) in xsim with the benchmark firmware and decodes the UART output. All kernels print PASS,
and the cycle counts are identical to `results/bench.json` (e.g. dot16_mac16x2 18,005 cycles,
matmul16_mac16x2 81,073 cycles).

In an earlier run with the default (non-directive) flow, the design missed 125 MHz by 43 ps on the same
block-RAM -> `mem_rdata_q` path; the default flow at 100 MHz met timing with +0.598 ns.
No board was used: this is a bitstream-ready implementation, not a hardware measurement.

## Methodology check (`report_methodology`)

| check | count | what it means here |
|---|---:|---|
| SYNTH-6: RAM block timing may be sub-optimal | 32 | The block RAM output register is not used. This is deliberate: it keeps the one-cycle memory latency identical to the simulation testbench, so cycle counts match. It is also why the critical path starts at the BRAM. |
| SYNTH-10: wide multiplier | 7 | The 33×33 PicoRV32 fast multiplier and the 32×32 MAC multiply are split across several DSP48 blocks. Advisory; the MAC's DSPs are pipelined (PIPE = 2) and are not on the critical path. |
| SYNTH-15: byte-wide write enable not inferred | 32 | Vivado chose a bit-sliced layout (32K × 1 per BRAM) for the 15-bit address because it is faster than byte-wide write enables; byte writes become per-BRAM write enables. No functional or resource impact. |

No critical warnings, no errors.
