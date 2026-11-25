#!/usr/bin/env python3
"""Unit tests of pcpi_mac for PIPE = 0, 1, 2, plus mutation tests.

Each mutation injects one realistic design bug into a copy of rtl/pcpi_mac.v and
re-runs the unit testbench (PIPE = 2, the final design). The testbench is expected
to FAIL on every mutant; the fraction that fails is the mutation detection rate.

Writes results/unit_tests.json and results/unit_tests.md.
"""
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SETTINGS = Path(os.environ.get("VIVADO_SETTINGS", Path.home() / "AMD/2025.2/Vivado/settings64.sh"))
RTL = ROOT / "rtl/pcpi_mac.v"

# name: (description, original text, mutated text)
MUTANTS = {
    "m01_drop_hi_lane": ("mac16x2 ignores the upper 16-bit lane",
                         "? p16_lo_r + p16_hi_r : p32_r;", "? p16_lo_r : p32_r;"),
    "m02_unsigned_lanes": ("16-bit lanes multiplied as unsigned",
                           "$signed(mul_a[15:0])  * $signed(mul_b[15:0])", "mul_a[15:0] * mul_b[15:0]"),
    "m03_hi_lane_wrong_half": ("upper lane uses the low half of rs2",
                               "$signed(mul_a[31:16]) * $signed(mul_b[31:16])",
                               "$signed(mul_a[31:16]) * $signed(mul_b[15:0])"),
    "m04_macrst_accumulates": ("macrst adds to the old accumulator instead of replacing it",
                               "(op_m == OP_MACRST) ? prod : acc + prod", "acc + prod"),
    "m05_macrd_updates_acc": ("macrd also writes the accumulator",
                              "if (result_valid && op_m != OP_MACRD)", "if (result_valid)"),
    "m06_macrd_returns_sum": ("macrd returns acc + prod instead of acc",
                              "(op_m == OP_MACRD) ? acc : acc_next", "acc_next"),
    "m07_decode_ignores_funct3": ("decoder ignores funct3 (answers foreign instructions)",
                                  "&& pcpi_insn[14:12] == 3'b000\n", "\n"),
    "m08_decode_ignores_funct7": ("decoder ignores funct7[6:2] (answers foreign instructions)",
                                  "&& pcpi_insn[31:27] == 5'b00000;", ";"),
    "m09_reissue_while_busy": ("new operation can start while one is in flight",
                               "start = resetn && insn_hit && !active;", "start = resetn && insn_hit;"),
    "m10_acc_reset_value": ("accumulator resets to 1 instead of 0",
                            "acc    <= 32'd0;", "acc    <= 32'd1;"),
}


def sim(name, pipe, rtl):
    work = ROOT / "build/unit" / name
    work.mkdir(parents=True, exist_ok=True)
    cmd = (f"source {SETTINGS} >/dev/null 2>&1; unset LIBRARY_PATH; "
           f"xvlog {rtl} {ROOT}/sim/tb_pcpi_mac.v > xvlog.log 2>&1 && "
           f"xelab -debug off --timescale 1ns/1ps -generic_top PIPE={pipe} tb_pcpi_mac -s t > xelab.log 2>&1 && "
           f"xsim t -R > sim.log 2>&1")
    subprocess.run(["bash", "-c", cmd], cwd=work)
    log = (work / "sim.log").read_text() if (work / "sim.log").exists() else ""
    m = re.search(r"UNIT TEST (PASS|FAIL)", log)
    checks = re.search(r"(\d+) checks", log)
    errs = re.search(r"(\d+) errors", log)
    return {"result": m.group(1) if m else "ERROR", "checks": int(checks.group(1)) if checks else 0,
            "errors": int(errs.group(1)) if errs else 0}


def job(item):
    name, spec = item
    if name.startswith("pipe"):
        return name, sim(name, spec, RTL)
    desc, orig, mut = spec
    src = RTL.read_text()
    assert src.count(orig) == 1, f"{name}: mutation anchor not unique"
    work = ROOT / "build/unit" / name
    work.mkdir(parents=True, exist_ok=True)
    (work / "pcpi_mac.v").write_text(src.replace(orig, mut))
    r = sim(name, 2, work / "pcpi_mac.v")
    r["description"] = desc
    return name, r


def main():
    items = [(f"pipe{p}", p) for p in (0, 1, 2)] + list(MUTANTS.items())
    with ThreadPoolExecutor(max_workers=6) as ex:
        res = dict(ex.map(job, items))
    pipes_ok = all(res[f"pipe{p}"]["result"] == "PASS" for p in (0, 1, 2))
    killed = [n for n in MUTANTS if res[n]["result"] == "FAIL"]
    rate = 100.0 * len(killed) / len(MUTANTS)
    out = {"pipes": {p: res[f"pipe{p}"] for p in (0, 1, 2)},
           "mutants": {n: res[n] for n in MUTANTS},
           "mutation_detection_rate_pct": rate}
    (ROOT / "results/unit_tests.json").write_text(json.dumps(out, indent=2))
    L = ["| PIPE | result | checks |", "|---:|---|---:|"]
    L += [f"| {p} | {res[f'pipe{p}']['result']} | {res[f'pipe{p}']['checks']} |" for p in (0, 1, 2)]
    L += ["", "| mutant (PIPE = 2) | injected bug | testbench result | errors reported |", "|---|---|---|---:|"]
    L += [f"| {n} | {MUTANTS[n][0]} | {res[n]['result']} | {res[n]['errors']} |" for n in MUTANTS]
    L += ["", f"**Mutation detection rate: {len(killed)}/{len(MUTANTS)} = {rate:.0f}%**"]
    (ROOT / "results/unit_tests.md").write_text("\n".join(L) + "\n")
    print("\n".join(L))
    return 0 if pipes_ok and len(killed) == len(MUTANTS) else 1


if __name__ == "__main__":
    sys.exit(main())
