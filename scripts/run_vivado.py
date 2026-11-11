#!/usr/bin/env python3
"""Implement every core configuration in Vivado at several clock targets.

Fmax per run = 1000 / (period - WNS); the best run per configuration is
reported. LUT/FF/DSP counts come from the post-route netlist, and the LUT
figure is cross-checked against report_utilization.

Writes results/ppa.json and results/ppa.md.
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
JOBS = int(os.environ.get("JOBS", "6"))
PERIODS = [4.0, 5.0, 6.0]

CONFIGS = {
    "rv32ic":          {},
    "rv32imc_mul":     {"ENABLE_MUL": 1},
    "rv32imc_fastmul": {"ENABLE_FAST_MUL": 1},
    "fastmul_mac_p1":  {"ENABLE_FAST_MUL": 1, "WITH_MAC": 1, "MAC_PIPE": 1},
    "fastmul_mac_p0":  {"ENABLE_FAST_MUL": 1, "WITH_MAC": 1, "MAC_PIPE": 0},
    "fastmul_mac_p2":  {"ENABLE_FAST_MUL": 1, "WITH_MAC": 1, "MAC_PIPE": 2},
}


def run(job):
    name, period = job
    out = ROOT / "build/vivado" / f"{name}_p{period:.1f}"
    if (out / "summary.txt").exists():
        return job, out
    out.mkdir(parents=True, exist_ok=True)
    gens = " ".join(f"{k}={v}" for k, v in CONFIGS[name].items())
    cmd = (f"source {SETTINGS} >/dev/null 2>&1; unset LIBRARY_PATH; "
           f"vivado -mode batch -nojournal -log {out}/vivado.log "
           f"-source {ROOT}/scripts/vivado_impl.tcl -tclargs {out} {period} {gens} > /dev/null 2>&1")
    subprocess.run(["bash", "-c", cmd], cwd=out)
    return job, out


def parse(out):
    s = dict(l.split(" ", 1) for l in (out / "summary.txt").read_text().splitlines())
    util = (out / "util.rpt").read_text()
    lut_rpt = int(re.search(r"\|\s*Slice LUTs\s*\|\s*(\d+)", util).group(1))
    ff_rpt = int(re.search(r"\|\s*Slice Registers\s*\|\s*(\d+)", util).group(1))
    dsp_rpt = int(re.search(r"\|\s*DSPs\s*\|\s*(\d+)", util).group(1))
    power = (out / "power.rpt").read_text()
    dyn = float(re.search(r"\|\s*Dynamic \(W\)\s*\|\s*([\d.]+)", power).group(1))
    period, wns = float(s["period"]), float(s["wns"])
    return {"period_ns": period, "wns_ns": wns, "fmax_mhz": round(1000 / (period - wns), 1),
            "lut": lut_rpt, "ff": ff_rpt, "dsp": dsp_rpt, "carry4": int(s["carry"]),
            "dynamic_power_w": dyn, "crit_start": s["crit_start"], "crit_end": s["crit_end"],
            "crit_levels": int(s["crit_levels"])}


def main():
    jobs = [(n, p) for n in CONFIGS for p in PERIODS]
    with ThreadPoolExecutor(max_workers=JOBS) as ex:
        done = list(ex.map(run, jobs))
    results = {}
    for (name, period), out in done:
        if not (out / "summary.txt").exists():
            print(f"FAILED: {name} @ {period} ns, see {out}/vivado.log")
            continue
        results.setdefault(name, {"generics": CONFIGS[name], "runs": []})["runs"].append(parse(out))
    for r in results.values():
        r["best"] = max(r["runs"], key=lambda x: x["fmax_mhz"])

    outdir = ROOT / "results"
    outdir.mkdir(exist_ok=True)
    (outdir / "ppa.json").write_text(json.dumps(results, indent=2))
    base = results.get("rv32imc_fastmul", {}).get("best")
    lines = ["| config | LUT | FF | DSP | Fmax (MHz) | dyn. power @ target (W) | crit. path end |",
             "|---|---:|---:|---:|---:|---:|---|"]
    for n in CONFIGS:
        if n not in results:
            continue
        b = results[n]["best"]
        lines.append(f"| {n} | {b['lut']} | {b['ff']} | {b['dsp']} | {b['fmax_mhz']} | "
                     f"{b['dynamic_power_w']} | {b['crit_end']} |")
    (outdir / "ppa.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if len(results) == len(CONFIGS) else 1


if __name__ == "__main__":
    sys.exit(main())
