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
| bitstream | generated (`build/bit125/fpga_top.bit`, not committed) |

Pre-bitstream check: `sim/tb_fpga_top.v` simulates the same top level (MMCM, reset, block RAM,
UART) in xsim with the benchmark firmware and decodes the UART output. All kernels print PASS,
and the cycle counts are identical to `results/bench.json` (e.g. dot16_mac16x2 18,005 cycles,
matmul16_mac16x2 81,073 cycles).

In an earlier run with the default (non-directive) flow, the design missed 125 MHz by 43 ps on the same
block-RAM -> `mem_rdata_q` path; the default flow at 100 MHz met timing with +0.598 ns.
No board was used: this is a bitstream-ready implementation, not a hardware measurement.
