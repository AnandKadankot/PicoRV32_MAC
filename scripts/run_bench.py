#!/usr/bin/env python3
"""Run the benchmark firmware on every core configuration in Vivado xsim.

For each configuration the full PicoRV32 + pcpi_mac RTL is simulated with the
matching firmware image, the RESULT lines are parsed, and every kernel value is
checked against an independent Python model of the same computation.

Writes results/bench.json and results/bench.md.
"""
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VIVADO_SETTINGS = Path(os.environ.get("VIVADO_SETTINGS",
                       Path.home() / "AMD/2025.2/Vivado/settings64.sh"))

# name: (generics, firmware image, description)
CONFIGS = {
    "rv32ic":          ({},                                          "bench_rv32ic",      "RV32IC, no multiplier (libgcc __mulsi3)"),
    "rv32imc_mul":     ({"ENABLE_MUL": 1},                           "bench_rv32imc",     "RV32IMC, PicoRV32 iterative multiplier"),
    "rv32imc_fastmul": ({"ENABLE_FAST_MUL": 1},                      "bench_rv32imc",     "RV32IMC, PicoRV32 DSP fast multiplier"),
    "fastmul_mac_p1":  ({"ENABLE_FAST_MUL": 1, "WITH_MAC": 1, "MAC_PIPE": 1}, "bench_rv32imc_mac", "RV32IMC fast mul + MAC unit (2-cycle)"),
    "fastmul_mac_p0":  ({"ENABLE_FAST_MUL": 1, "WITH_MAC": 1, "MAC_PIPE": 0}, "bench_rv32imc_mac", "RV32IMC fast mul + MAC unit (1-cycle)"),
    "fastmul_mac_p2":  ({"ENABLE_FAST_MUL": 1, "WITH_MAC": 1, "MAC_PIPE": 2}, "bench_rv32imc_mac", "RV32IMC fast mul + MAC unit (3-cycle, DSP-pipelined)"),
    # no compressed ISA: every instruction word-aligned, isolates fetch-alignment effects
    "nc_fastmul":      ({"ENABLE_FAST_MUL": 1, "COMPRESSED_ISA": 0},  "bench_rv32im",      "RV32IM (no C), DSP fast multiplier"),
    "nc_fastmul_mac_p1": ({"ENABLE_FAST_MUL": 1, "WITH_MAC": 1, "MAC_PIPE": 1, "COMPRESSED_ISA": 0}, "bench_rv32im_mac", "RV32IM (no C) fast mul + MAC unit (2-cycle)"),
}

RTL = [ROOT / "third_party/picorv32/picorv32.v", ROOT / "rtl/pcpi_mac.v",
       ROOT / "rtl/core_top.v", ROOT / "sim/tb_soc.v"]


# ---------------------------------------------------------------- reference model
def s32(x):
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x & 0x80000000 else x


def s16(x):
    x &= 0xFFFF
    return x - (1 << 16) if x & 0x8000 else x


def reference(n=1024, m=16):
    state = 12345

    def lcg():
        nonlocal state
        state = (state * 1103515245 + 12345) & 0xFFFFFFFF
        return state

    a32, b32, a16, b16 = [], [], [], []
    for _ in range(n):
        a32.append(s32(lcg())); b32.append(s32(lcg()))
        a16.append(s16(lcg() >> 16)); b16.append(s16(lcg() >> 16))
    ma = [[0] * m for _ in range(m)]
    mbt = [[0] * m for _ in range(m)]
    for i in range(m):
        for j in range(m):
            ma[i][j] = s16(lcg() >> 16)
            mbt[i][j] = s16(lcg() >> 16)

    dot32 = s32(sum(x * y for x, y in zip(a32, b32)))
    dot16 = s32(sum(x * y for x, y in zip(a16, b16)))
    chk = 0
    for i in range(m):
        for j in range(m):
            s = s32(sum(ma[i][k] * mbt[j][k] for k in range(m)))
            chk = s32(chk ^ s32(s + i * m + j))
    return {"dot32": dot32, "dot16": dot16, "matmul16": chk}


# ---------------------------------------------------------------- simulation
def run_config(name):
    generics, fw, _ = CONFIGS[name]
    work = ROOT / "build/sim" / name
    work.mkdir(parents=True, exist_ok=True)
    hexfile = ROOT / "sw/build" / f"{fw}.hex"
    gen = " ".join(f'-generic_top "{k}={v}"' for k, v in generics.items())
    cmd = (f"source {VIVADO_SETTINGS} >/dev/null 2>&1; unset LIBRARY_PATH; "
           f"xvlog {' '.join(map(str, RTL))} > xvlog.log 2>&1 && "
           f"xelab -debug off --timescale 1ns/1ps {gen} tb_soc -s soc > xelab.log 2>&1 && "
           f"xsim soc -R -testplusarg FIRMWARE={hexfile} > xsim.log 2>&1")
    subprocess.run(["bash", "-c", cmd], cwd=work)
    return name, (work / "xsim.log").read_text() if (work / "xsim.log").exists() else ""


def main():
    subprocess.run(["make", "-C", str(ROOT / "sw")], check=True,
                   stdout=subprocess.DEVNULL)
    ref = reference()
    with ThreadPoolExecutor(max_workers=len(CONFIGS)) as ex:
        logs = dict(ex.map(run_config, CONFIGS))

    results, ok = {}, True
    for name, log in logs.items():
        kernels = {}
        for k, cyc, val, status in re.findall(
                r"RESULT (\S+) cycles=(\d+) value=(-?\d+) (PASS|FAIL)", log):
            expect = ref[k.split("_")[0]]
            host_ok = int(val) == expect
            kernels[k] = {"cycles": int(cyc), "value": int(val),
                          "fw_check": status, "host_check": "PASS" if host_ok else "FAIL"}
            ok &= status == "PASS" and host_ok
        m = re.search(r"EXIT code=(\d+) cycles=(\d+)", log)
        if not m or not kernels:
            print(f"[{name}] simulation did not complete:\n{log[-2000:]}")
            ok = False
        results[name] = {"description": CONFIGS[name][2], "generics": CONFIGS[name][0],
                         "exit_code": int(m.group(1)) if m else None, "kernels": kernels}

    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    (out / "bench.json").write_text(json.dumps(results, indent=2))

    # markdown summary
    names = list(CONFIGS)
    kernels = sorted({k for r in results.values() for k in r["kernels"]},
                     key=lambda k: (k.split("_")[0], len(k)))
    lines = ["| kernel | " + " | ".join(names) + " |",
             "|---|" + "---:|" * len(names)]
    for k in kernels:
        row = [str(results[n]["kernels"].get(k, {}).get("cycles", "–")) for n in names]
        lines.append(f"| {k} | " + " | ".join(row) + " |")
    (out / "bench.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("\nALL CHECKS PASS" if ok else "\nSOME CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
